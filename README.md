# SuperCluster Protocol – Smart Contract Suite

This repository contains the on-chain logic for **SuperCluster**, a modular liquidity manager that mints rebasing staking tokens, routes deposits to strategy pilots, and coordinates queued withdrawals for testnet environments (Base Sepolia by default).

## High-Level Architecture

- **SuperCluster.sol**  
  Core entry point. Deploys the rebasing `SToken`, wrapped `WsToken`, and connects to a `Withdraw` manager. Handles user deposits, mints/burns staking shares, tracks supported tokens, and delegates capital to pilots.

- **Pilot.sol**  
  Strategy controller per pool. Maintains a list of adapters (e.g., Mock Aave, Mock Morpho), enforces allocation percentages, invests/divests/harvests, and reports AUM back to SuperCluster.

- **Adapters (AaveAdapter, MorphoAdapter, …)**  
  Per-protocol wrappers that normalize deposit, withdraw, balance, reward flows. Reference mocks imitate behaviour of real lending markets.

- **Tokens (SToken, WsToken, MockUSDC, Withdraw queue)**  
  `SToken` is rebasing (shares based). `WsToken` provides non-rebasing wrapping. `Withdraw.sol` manages delayed withdrawal requests, supporting funding/finalization by an operator.

- **Mocks**  
  Mock protocols let pilots accrue interest or test rebalances locally without touching mainnet.

## Functional Flow

1. **Deposit / Stake**
   - User approves SuperCluster to spend the base token (MockUSDC).
   - `SuperCluster.deposit(pilot, token, amount)` mints `sToken`, approves the pilot, and triggers `Pilot.receiveAndInvest`.
   - Pilot distributes to active adapters based on saved allocations.

2. **Rebasing & AUM Tracking**
   - SuperCluster can call `calculateTotalAUM()` and update the rebasing supply via `rebase()` or `rebaseWithAUM`.
   - Pilots expose `getTotalValue()` to contribute to aggregate AUM.

3. **Withdraw**
   - User requests a withdrawal through `SuperCluster.withdraw(token, amount)`.
   - Contract burns the user’s `sToken`, records the withdrawal request via `Withdraw.autoRequest`, and emits `TokenWithdrawn`.
   - Operators must fund the withdraw manager (`Withdraw.fund`) and mark requests ready via `finalizeWithdraw`. Users then call `claim`.

4. **Pilot Management**
   - Admin sets strategy via `Pilot.setPilotStrategy`, enabling/disabling adapters, and calling `invest`, `divest`, or `harvest`.
   - Emergency escape hatches (`emergencyWithdraw`, `withdrawForUser`) allow reclaiming assets when needed.

## Features

- Rebasing staking token (`SToken`) with optional wrapped version (`WsToken`) for DeFi integrations.
- Pluggable strategy pilots with adapter abstraction.
- Mock protocol adapters (Aave, Morpho) for local interest accrual tests.
- Withdrawal queue contract with request/finalize/claim lifecycle.
- Faucet contract (MockUSDC) for local/testnet token distribution.
- Hook-friendly TypeScript ABIs exported for SuperCluster, Pilot, Adapters, Faucet.

## Known Issues & Mitigations

| Issue                                                                                                     | Impact                                                                    | Suggested Fix                                                                                                                                 |
| --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `SuperCluster.tokenBalances[token]` is decremented on withdraw but never incremented during deposit       | Withdrawals revert with `InsufficientBalance` even when user holds sToken | Increment `tokenBalances[token]` inside `deposit`, or replace the mapping with real balance checks (`IERC20(token).balanceOf(address(this))`) |
| Withdraw queue requires operator intervention                                                             | Users block until funding/finalization happen                             | Provide backend or script calling `Pilot.withdrawForUser`, `Withdraw.fund`, `Withdraw.finalizeWithdraw`, and expose operator UI               |
| Mock adapters return simplistic APYs                                                                      | Production yield data missing                                             | Integrate real protocol adapters or enrich mocks with configurable rates                                                                      |
| `receiveAndInvest` approves self (`IERC20.approve(address(this), amount)`) before `_distributeToAdapters` | Redundant approval (no functional break)                                  | Remove unused approval to reduce gas                                                                                                          |

Scripts can be added to `script/` for deployment via `forge script ... --rpc-url ... --private-key ...`.

## Workflow

1. Deploy contracts (`SuperCluster`, `Pilot`, adapters, tokens, withdraw manager, faucet) to Base Sepolia.
2. Configure environment variables in `NEXT_PUBLIC_*` (front-end).
3. Register supported pilot/token pairs via `SuperCluster.registerPilot`.
4. Set withdraw manager: `SuperCluster.setWithdrawManager(address)`.
5. Fund faucet with MockUSDC or mint via contract `mint`.
6. For each withdrawal request, operator should:
   - Call `Pilot.withdrawForUser(amount)` to unwind liquidity.
   - Transfer underlying to withdraw manager and call `Withdraw.fund(amount)`.
   - Mark ready via `Withdraw.finalizeWithdraw(id, baseAmount)`.
   - Users can then `Withdraw.claim(id)`.

## Directory Overview

- `src/` – Solidity contracts (core, pilots, adapters, tokens, withdraw manager, mocks).
- `script/` – Forge deployment scripts (placeholder).
- `test/` – Solidity tests (add coverage for pilots, adapters, withdraw).
- `lib/` – External dependencies (OpenZeppelin, etc.).
- `broadcast/` – Deployment artifacts (Forge).
- `UI/` _(in adjacent repo)_ – Front-end pages for staking, operator, faucet.

## Extending the System

- **Add real adapters** by implementing `IAdapter` and registering via `Pilot.setPilotStrategy`.
- **Improve withdraw UX** by automating operator tasks (cron job or keeper).
- **Enforce deposit accounting**: fix `tokenBalances` mapping or remove it if AUM calculation suffices.

---
