;; SalaryRiver - Basic Payroll Streaming Contract (Stage 1)
;; Simple continuous salary payments with hourly compensation

(define-constant PAYROLL_ADMIN tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u200))
(define-constant ERR_EMPLOYEE_NOT_FOUND (err u201))
(define-constant ERR_INSUFFICIENT_FUNDS (err u202))
(define-constant ERR_PAYROLL_EXISTS (err u203))
(define-constant ERR_INVALID_RATE (err u204))

;; Simple employee payroll structure
(define-map employee-payrolls
  { payroll-id: uint }
  {
    employer: principal,
    employee: principal,
    hourly-rate: uint,
    start-time: uint,
    total-budget: uint,
    amount-claimed: uint,
    is-active: bool
  }
)

;; Company balances
(define-map company-balances
  { company: principal }
  { balance: uint }
)

;; Payroll counter
(define-data-var payroll-counter uint u0)

;; Get current time
(define-read-only (get-current-time)
  block-height
)

;; Get company balance
(define-read-only (get-company-balance (company principal))
  (default-to u0 (get balance (map-get? company-balances { company: company })))
)

;; Get payroll info
(define-read-only (get-payroll-info (payroll-id uint))
  (map-get? employee-payrolls { payroll-id: payroll-id })
)

;; Calculate earned salary
(define-read-only (calculate-earned-salary (payroll-id uint))
  (match (map-get? employee-payrolls { payroll-id: payroll-id })
    payroll-info
    (let (
      (current-time (get-current-time))
      (start-time (get start-time payroll-info))
      (rate (get hourly-rate payroll-info))
      (claimed (get amount-claimed payroll-info))
      (budget (get total-budget payroll-info))
      (is-active (get is-active payroll-info))
    )
    (if is-active
      (let (
        (work-time (if (>= current-time start-time) (- current-time start-time) u0))
        (total-earned (* work-time rate))
        (unclaimed (if (> total-earned claimed) (- total-earned claimed) u0))
        (available (if (> budget claimed) (- budget claimed) u0))
      )
      (if (< unclaimed available) unclaimed available))
      u0))
    u0)
)

;; Add funds to company
(define-public (add-company-funds (amount uint))
  (let (
    (current-balance (get-company-balance tx-sender))
  )
  (map-set company-balances
    { company: tx-sender }
    { balance: (+ current-balance amount) }
  )
  (ok (+ current-balance amount)))
)

;; Create new payroll
(define-public (create-payroll 
  (employee principal) 
  (hourly-rate uint) 
  (budget uint))
  (let (
    (new-payroll-id (+ (var-get payroll-counter) u1))
    (company-balance (get-company-balance tx-sender))
    (current-time (get-current-time))
  )
  (asserts! (> hourly-rate u0) ERR_INVALID_RATE)
  (asserts! (> budget u0) ERR_INVALID_RATE)
  (asserts! (>= company-balance budget) ERR_INSUFFICIENT_FUNDS)
  
  ;; Deduct budget from company
  (map-set company-balances
    { company: tx-sender }
    { balance: (- company-balance budget) }
  )
  
  ;; Create payroll
  (map-set employee-payrolls
    { payroll-id: new-payroll-id }
    {
      employer: tx-sender,
      employee: employee,
      hourly-rate: hourly-rate,
      start-time: current-time,
      total-budget: budget,
      amount-claimed: u0,
      is-active: true
    }
  )
  
  ;; Update counter
  (var-set payroll-counter new-payroll-id)
  
  (ok new-payroll-id))
)

;; Claim earned salary
(define-public (claim-earned-salary (payroll-id uint))
  (match (map-get? employee-payrolls { payroll-id: payroll-id })
    payroll-info
    (let (
      (employee (get employee payroll-info))
      (earned-amount (calculate-earned-salary payroll-id))
      (current-claimed (get amount-claimed payroll-info))
      (employee-balance (get-company-balance employee))
    )
    (asserts! (is-eq tx-sender employee) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active payroll-info) ERR_EMPLOYEE_NOT_FOUND)
    (asserts! (> earned-amount u0) ERR_INSUFFICIENT_FUNDS)
    
    ;; Update claimed amount
    (map-set employee-payrolls
      { payroll-id: payroll-id }
      (merge payroll-info { amount-claimed: (+ current-claimed earned-amount) })
    )
    
    ;; Add to employee balance
    (map-set company-balances
      { company: employee }
      { balance: (+ employee-balance earned-amount) }
    )
    
    (ok earned-amount))
    ERR_EMPLOYEE_NOT_FOUND)
)

;; Stop payroll
(define-public (stop-payroll (payroll-id uint))
  (match (map-get? employee-payrolls { payroll-id: payroll-id })
    payroll-info
    (let (
      (employer (get employer payroll-info))
      (final-payment (calculate-earned-salary payroll-id))
      (budget (get total-budget payroll-info))
      (claimed (get amount-claimed payroll-info))
      (refund (if (> (- budget claimed) final-payment) 
                (- (- budget claimed) final-payment) 
                u0))
      (employer-balance (get-company-balance employer))
      (employee-balance (get-company-balance (get employee payroll-info)))
    )
    (asserts! (is-eq tx-sender employer) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active payroll-info) ERR_EMPLOYEE_NOT_FOUND)
    
    ;; Deactivate payroll
    (map-set employee-payrolls
      { payroll-id: payroll-id }
      (merge payroll-info { is-active: false })
    )
    
    ;; Pay final amount to employee
    (if (> final-payment u0)
      (begin
        (map-set company-balances
          { company: (get employee payroll-info) }
          { balance: (+ employee-balance final-payment) })
        (map-set employee-payrolls
          { payroll-id: payroll-id }
          (merge payroll-info { 
            amount-claimed: (+ claimed final-payment),
            is-active: false 
          })))
      true)
    
    ;; Refund remaining to employer
    (if (> refund u0)
      (map-set company-balances
        { company: employer }
        { balance: (+ employer-balance refund) })
      true)
    
    (ok { final-payment: final-payment, refund: refund }))
    ERR_EMPLOYEE_NOT_FOUND)
)

;; Get total payrolls created
(define-read-only (get-payroll-count)
  (var-get payroll-counter)
)