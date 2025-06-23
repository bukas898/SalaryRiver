;; SalaryRiver - Real-time Payroll Streaming Contract
;; Enables continuous salary payments with per-second compensation

(define-constant PAYROLL_ADMIN tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u200))
(define-constant ERR_EMPLOYEE_NOT_FOUND (err u201))
(define-constant ERR_INSUFFICIENT_PAYROLL (err u202))
(define-constant ERR_PAYROLL_EXISTS (err u203))
(define-constant ERR_INVALID_SALARY (err u204))
(define-constant ERR_EMPLOYMENT_TERMINATED (err u205))
(define-constant ERR_PAYROLL_FROZEN (err u206))

;; Employee payroll data structure
(define-map employee-payrolls
  { payroll-id: uint }
  {
    employer: principal,
    employee: principal,
    hourly-rate: uint,           ;; Salary rate per second
    employment-start: uint,      ;; When employment started
    contract-end: (optional uint), ;; Optional employment end date
    total-allocated: uint,       ;; Total salary budget allocated
    salary-claimed: uint,        ;; Amount already claimed by employee
    employment-active: bool,     ;; Employment status
    payroll-frozen: bool,        ;; Frozen payroll status
    freeze-timestamp: (optional uint) ;; When payroll was frozen
  }
)

;; Track company treasury balances
(define-map company-treasury
  { company: principal }
  { funds: uint }
)

;; Track payroll counter
(define-data-var payroll-counter uint u0)

;; Track employee counts per company
(define-map company-employees
  { company: principal }
  { active-count: uint, total-count: uint }
)

;; Map company to employee payroll IDs
(define-map company-payroll-registry
  { company: principal, employee-index: uint }
  { payroll-id: uint }
)

(define-map employee-work-history
  { employee: principal, job-index: uint }
  { payroll-id: uint }
)

;; Get current timestamp
(define-read-only (get-current-timestamp)
  block-height
)

;; Get company treasury balance
(define-read-only (get-treasury-balance (company principal))
  (default-to u0 (get funds (map-get? company-treasury { company: company })))
)

;; Get employee payroll details
(define-read-only (get-payroll-details (payroll-id uint))
  (map-get? employee-payrolls { payroll-id: payroll-id })
)

;; Calculate accrued salary for withdrawal
(define-read-only (calculate-accrued-salary (payroll-id uint))
  (match (map-get? employee-payrolls { payroll-id: payroll-id })
    payroll-data
    (let (
      (current-time (get-current-timestamp))
      (start-time (get employment-start payroll-data))
      (end-time (get contract-end payroll-data))
      (rate (get hourly-rate payroll-data))
      (claimed (get salary-claimed payroll-data))
      (allocated (get total-allocated payroll-data))
      (active (get employment-active payroll-data))
      (frozen (get payroll-frozen payroll-data))
      (freeze-time (get freeze-timestamp payroll-data))
    )
    (if (and active (not frozen))
      (let (
        (effective-end (match end-time
          some-end some-end
          current-time))
        (actual-end (if (> effective-end current-time) current-time effective-end))
        (work-duration (if (>= actual-end start-time) (- actual-end start-time) u0))
        (total-earned (* work-duration rate))
        (available (if (> total-earned claimed) (- total-earned claimed) u0))
        (max-claimable (if (> allocated claimed) (- allocated claimed) u0))
      )
      (if (< available max-claimable) available max-claimable))
      u0))
    u0)
)

;; Fund company treasury
(define-public (fund-treasury (amount uint))
  (let (
    (current-funds (get-treasury-balance tx-sender))
    (new-balance (+ current-funds amount))
  )
  (map-set company-treasury
    { company: tx-sender }
    { funds: new-balance }
  )
  (ok new-balance))
)

;; Withdraw from company treasury
(define-public (withdraw-treasury (amount uint))
  (let (
    (current-funds (get-treasury-balance tx-sender))
  )
  (if (>= current-funds amount)
    (begin
      (map-set company-treasury
        { company: tx-sender }
        { funds: (- current-funds amount) }
      )
      (ok (- current-funds amount)))
    ERR_INSUFFICIENT_PAYROLL))
)

;; Hire employee and setup payroll stream
(define-public (hire-employee 
  (employee principal) 
  (hourly-rate uint) 
  (salary-budget uint)
  (contract-duration (optional uint)))
  (let (
    (payroll-id (+ (var-get payroll-counter) u1))
    (company-funds (get-treasury-balance tx-sender))
    (current-time (get-current-timestamp))
    (contract-end (match contract-duration
      some-duration (some (+ current-time some-duration))
      none))
    (company-stats (default-to { active-count: u0, total-count: u0 } 
                   (map-get? company-employees { company: tx-sender })))
  )
  (asserts! (> hourly-rate u0) ERR_INVALID_SALARY)
  (asserts! (> salary-budget u0) ERR_INVALID_SALARY)
  (asserts! (>= company-funds salary-budget) ERR_INSUFFICIENT_PAYROLL)
  (asserts! (is-none (map-get? employee-payrolls { payroll-id: payroll-id })) ERR_PAYROLL_EXISTS)
  
  ;; Deduct budget from company treasury
  (map-set company-treasury
    { company: tx-sender }
    { funds: (- company-funds salary-budget) }
  )
  
  ;; Create payroll record
  (map-set employee-payrolls
    { payroll-id: payroll-id }
    {
      employer: tx-sender,
      employee: employee,
      hourly-rate: hourly-rate,
      employment-start: current-time,
      contract-end: contract-end,
      total-allocated: salary-budget,
      salary-claimed: u0,
      employment-active: true,
      payroll-frozen: false,
      freeze-timestamp: none
    }
  )
  
  ;; Update payroll counter
  (var-set payroll-counter payroll-id)
  
  ;; Update company employee registry
  (map-set company-payroll-registry
    { company: tx-sender, employee-index: (get total-count company-stats) }
    { payroll-id: payroll-id }
  )
  
  (map-set employee-work-history
    { employee: employee, job-index: u0 }
    { payroll-id: payroll-id }
  )
  
  ;; Update company stats
  (map-set company-employees
    { company: tx-sender }
    { active-count: (+ (get active-count company-stats) u1), 
      total-count: (+ (get total-count company-stats) u1) }
  )
  
  (ok payroll-id)))

;; Claim accrued salary
(define-public (claim-salary (payroll-id uint))
  (match (map-get? employee-payrolls { payroll-id: payroll-id })
    payroll-data
    (let (
      (employee (get employee payroll-data))
      (accrued-amount (calculate-accrued-salary payroll-id))
      (current-claimed (get salary-claimed payroll-data))
      (employee-balance (get-treasury-balance employee))
    )
    (asserts! (is-eq tx-sender employee) ERR_NOT_AUTHORIZED)
    (asserts! (get employment-active payroll-data) ERR_EMPLOYMENT_TERMINATED)
    (asserts! (> accrued-amount u0) ERR_INSUFFICIENT_PAYROLL)
    
    ;; Update payroll claimed amount
    (map-set employee-payrolls
      { payroll-id: payroll-id }
      (merge payroll-data { salary-claimed: (+ current-claimed accrued-amount) })
    )
    
    ;; Add to employee balance
    (map-set company-treasury
      { company: employee }
      { funds: (+ employee-balance accrued-amount) }
    )
    
    (ok accrued-amount))
    ERR_EMPLOYEE_NOT_FOUND)
)

;; Freeze payroll (employer only)
(define-public (freeze-payroll (payroll-id uint))
  (match (map-get? employee-payrolls { payroll-id: payroll-id })
    payroll-data
    (let (
      (employer (get employer payroll-data))
      (current-time (get-current-timestamp))
    )
    (asserts! (is-eq tx-sender employer) ERR_NOT_AUTHORIZED)
    (asserts! (get employment-active payroll-data) ERR_EMPLOYMENT_TERMINATED)
    (asserts! (not (get payroll-frozen payroll-data)) ERR_PAYROLL_FROZEN)
    
    (map-set employee-payrolls
      { payroll-id: payroll-id }
      (merge payroll-data { 
        payroll-frozen: true,
        freeze-timestamp: (some current-time)
      })
    )
    
    (ok true))
    ERR_EMPLOYEE_NOT_FOUND)
)

;; Unfreeze payroll (employer only)
(define-public (unfreeze-payroll (payroll-id uint))
  (match (map-get? employee-payrolls { payroll-id: payroll-id })
    payroll-data
    (let (
      (employer (get employer payroll-data))
      (current-time (get-current-timestamp))
      (freeze-time (get freeze-timestamp payroll-data))
    )
    (asserts! (is-eq tx-sender employer) ERR_NOT_AUTHORIZED)
    (asserts! (get employment-active payroll-data) ERR_EMPLOYMENT_TERMINATED)
    (asserts! (get payroll-frozen payroll-data) ERR_PAYROLL_FROZEN)
    
    ;; Adjust start time for frozen period
    (let (
      (frozen-duration (match freeze-time
        some-freeze-time (- current-time some-freeze-time)
        u0))
      (new-start-time (+ (get employment-start payroll-data) frozen-duration))
      (new-end-time (match (get contract-end payroll-data)
        some-end (some (+ some-end frozen-duration))
        none))
    )
    
    (map-set employee-payrolls
      { payroll-id: payroll-id }
      (merge payroll-data { 
        payroll-frozen: false,
        freeze-timestamp: none,
        employment-start: new-start-time,
        contract-end: new-end-time
      })
    )
    
    (ok true)))
    ERR_EMPLOYEE_NOT_FOUND)
)

;; Terminate employment
(define-public (terminate-employment (payroll-id uint))
  (match (map-get? employee-payrolls { payroll-id: payroll-id })
    payroll-data
    (let (
      (employer (get employer payroll-data))
      (accrued-for-employee (calculate-accrued-salary payroll-id))
      (total-allocated (get total-allocated payroll-data))
      (claimed (get salary-claimed payroll-data))
      (refund-amount (if (> (- total-allocated claimed) accrued-for-employee)
                       (- (- total-allocated claimed) accrued-for-employee)
                       u0))
      (employer-funds (get-treasury-balance employer))
      (employee-funds (get-treasury-balance (get employee payroll-data)))
    )
    (asserts! (is-eq tx-sender employer) ERR_NOT_AUTHORIZED)
    (asserts! (get employment-active payroll-data) ERR_EMPLOYMENT_TERMINATED)
    
    ;; Mark employment as terminated
    (map-set employee-payrolls
      { payroll-id: payroll-id }
      (merge payroll-data { employment-active: false })
    )
    
    ;; Refund remaining budget to employer
    (if (> refund-amount u0)
      (map-set company-treasury
        { company: employer }
        { funds: (+ employer-funds refund-amount) })
      true)
    
    ;; Pay final accrued salary to employee
    (if (> accrued-for-employee u0)
      (begin
        (map-set company-treasury
          { company: (get employee payroll-data) }
          { funds: (+ employee-funds accrued-for-employee) })
        (map-set employee-payrolls
          { payroll-id: payroll-id }
          (merge payroll-data { 
            salary-claimed: (+ claimed accrued-for-employee),
            employment-active: false 
          })))
      true)
    
    (ok { refunded: refund-amount, final-pay: accrued-for-employee }))
    ERR_EMPLOYEE_NOT_FOUND)
)

;; Increase salary budget
(define-public (increase-salary-budget (payroll-id uint) (additional-amount uint))
  (match (map-get? employee-payrolls { payroll-id: payroll-id })
    payroll-data
    (let (
      (employer (get employer payroll-data))
      (employer-funds (get-treasury-balance employer))
      (current-allocated (get total-allocated payroll-data))
    )
    (asserts! (is-eq tx-sender employer) ERR_NOT_AUTHORIZED)
    (asserts! (get employment-active payroll-data) ERR_EMPLOYMENT_TERMINATED)
    (asserts! (>= employer-funds additional-amount) ERR_INSUFFICIENT_PAYROLL)
    (asserts! (> additional-amount u0) ERR_INVALID_SALARY)
    
    ;; Deduct from employer treasury
    (map-set company-treasury
      { company: employer }
      { funds: (- employer-funds additional-amount) }
    )
    
    ;; Update allocated budget
    (map-set employee-payrolls
      { payroll-id: payroll-id }
      (merge payroll-data { total-allocated: (+ current-allocated additional-amount) })
    )
    
    (ok (+ current-allocated additional-amount)))
    ERR_EMPLOYEE_NOT_FOUND)
)

;; Get company employee statistics
(define-read-only (get-company-stats (company principal))
  (default-to { active-count: u0, total-count: u0 }
    (map-get? company-employees { company: company }))
)

;; Get payroll ID by company and employee index
(define-read-only (get-company-employee-payroll (company principal) (index uint))
  (map-get? company-payroll-registry { company: company, employee-index: index })
)

;; Get total payroll count
(define-read-only (get-total-payrolls)
  (var-get payroll-counter)
)

;; Check if employment has naturally ended
(define-read-only (has-employment-ended (payroll-id uint))
  (match (map-get? employee-payrolls { payroll-id: payroll-id })
    payroll-data
    (let (
      (current-time (get-current-timestamp))
      (end-time (get contract-end payroll-data))
    )
    (or 
      (not (get employment-active payroll-data))
      (match end-time
        some-end (>= current-time some-end)
        false)
      (>= (get salary-claimed payroll-data) (get total-allocated payroll-data))))
    false)
)