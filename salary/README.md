# SalaryRiver 💸  
**Real-time Payroll Streaming Contract on Stacks**

SalaryRiver enables **continuous, per-second salary payments** between employers and employees using Clarity smart contracts on the Stacks blockchain. This system facilitates real-time payroll streaming, transparent compensation tracking, and flexible employment management.

---

## 🚀 Features

- ⏱ **Per-Second Salary Accrual**: Employees earn their salary every second they remain employed.
- 🔐 **Employer-Controlled Payroll Streams**: Employers fund and manage individualized payroll allocations.
- ❄️ **Freeze & Unfreeze Payroll**: Employers can pause/resume salary streams during disputes or transitions.
- 🧾 **Transparent Employment History**: Maintains a historical registry of employee payrolls.
- 💼 **Company-Level Treasury Management**: Manage and audit employer-funded salary budgets.
- ✅ **Fair Termination & Refunds**: Automatically refunds unused salary to employers and pays final earnings to employees.

---

## 🛠 Contract Structure

### 📂 Maps

- `employee-payrolls`: Stores payroll stream details by unique ID.
- `company-treasury`: Tracks company funds.
- `company-employees`: Tracks active and total employee count.
- `company-payroll-registry`: Maps company & index to payroll ID.
- `employee-work-history`: Records job history for each employee.

### 📊 Variables

- `payroll-counter`: Unique payroll stream ID counter.

---

## 🧾 Core Functions

### 📥 Treasury Management

- `fund-treasury (amount)`: Add funds to employer’s treasury.
- `withdraw-treasury (amount)`: Withdraw unused funds.

### 👷 Employment Management

- `hire-employee (employee, hourly-rate, salary-budget, duration)`: Start a new payroll stream.
- `terminate-employment (payroll-id)`: Ends employment, pays final earnings, refunds employer.

### 💰 Salary Streaming

- `claim-salary (payroll-id)`: Employee claims accrued salary.
- `increase-salary-budget (payroll-id, amount)`: Add more funds to a payroll.

### ❄️ Payroll Control

- `freeze-payroll (payroll-id)`: Temporarily halt salary streaming.
- `unfreeze-payroll (payroll-id)`: Resume salary streaming and adjust timing.

### 🔎 Read-only Queries

- `get-payroll-details (payroll-id)`
- `calculate-accrued-salary (payroll-id)`
- `get-treasury-balance (company)`
- `get-company-stats (company)`
- `get-company-employee-payroll (company, index)`
- `get-total-payrolls`
- `has-employment-ended (payroll-id)`

---

## 🔐 Access Control

- Only employers (the `tx-sender`) can:
  - Fund/withdraw from their treasury
  - Hire, freeze/unfreeze, or terminate employees
  - Increase salary budgets

- Only employees can claim their salaries.

---

## 🧪 Error Codes

| Code        | Meaning                        |
|-------------|--------------------------------|
| `u200`      | Not authorized                 |
| `u201`      | Employee not found             |
| `u202`      | Insufficient payroll funds     |
| `u203`      | Payroll already exists         |
| `u204`      | Invalid salary or budget       |
| `u205`      | Employment already terminated  |
| `u206`      | Payroll already frozen         |

---

## ✅ Example Use Case

1. **Employer A** funds treasury with 10,000 STX.
2. They hire **Employee B** at 1 STX/sec for a 1-hour contract.
3. Employee B can claim salary anytime during the hour.
4. Employer can freeze the stream, unfreeze, or terminate at any point.
5. Upon termination, Employee gets accrued amount, and remaining funds are refunded to Employer A.

---

## 📜 Deployment Notes

- Built with **Clarity** on the Stacks blockchain.
- Uses `block-height` for timestamping (approximates seconds).

---

## 🔮 Potential Enhancements

- Streamable NFTs or reputation tokens per completed contract.
- DAO-based employer reputation scoring.
- Multi-signature employer treasury.
- Real-time front-end payroll visualizer.
