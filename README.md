# E-Transaction

On-chain wallet registry and transaction tracking backend, built with [Foundry](https://book.getfoundry.sh/). It lets users register a wallet with a username + PIN, tracks ETH sent/received between registered wallets, and stores per-transaction records (including live USD value and gas fees via Chainlink) with monthly and lifetime stats.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Contracts](#contracts)
- [Deployed Addresses](#deployed-addresses)
- [Project Structure](#project-structure)
- [Tech Stack](#tech-stack)
- [Getting Started](#getting-started)
- [Testing](#testing)
- [Deployment](#deployment)
- [Environment Variables](#environment-variables)
- [License](#license)

---

## Overview

E-Transaction is a self-contained smart contract system, split into three core contracts that separate concerns cleanly:

1. **`WalletRegistry`** — identity layer (username + PIN, registration state)
2. **`TransactionTracker`** — moves ETH between registered wallets and logs basic transfer data
3. **`TrackerStorage`** — the analytics layer: records every transaction with live USD pricing (via Chainlink), and rolls up monthly + lifetime stats per wallet

A `PriceConverter` library wraps Chainlink's `AggregatorV3Interface` with safety checks (stale price, zero/negative price, round mismatch) so the system gets reliable ETH → USD conversions.

## Architecture

```
                 registerWallet() / setPin()
        User ───────────────────────────────► WalletRegistry
                                                    ▲
                                                    │ isWalletRegistered()
                                                    │
        User ── sendEth() ──► TransactionTracker ──┘
                                    │
                                    │ (off-chain / relayer calls)
                                    ▼
                             TrackerStorage ──► PriceConverter ──► Chainlink
                                    │                                Price Feed
                                    ▼
                     TxRecord[] + MonthlyStats + Lifetime Stats
```

- `TransactionTracker` and `TrackerStorage` both depend on `WalletRegistry` to gate actions to registered wallets only (`onlyRegistered` modifiers).
- `TrackerStorage.recordTransaction()` is restricted to a single `s_authorizedTracker` address (set by the owner post-deploy) — this is what `TransactionTracker` or a backend relayer calls to persist a record.
- All three contracts use OpenZeppelin's `Ownable`, `ReentrancyGuard`, and (where relevant) `Pausable`.

## Contracts

### `WalletRegistry.sol`

Identity and access-control root for the system.

- `registerWallet(username)` — registers `msg.sender` with a username (max 32 chars), rejects duplicates
- `removeWallet()` — deactivates a wallet, resets PIN state
- `updateUserName(newUsername)` — rename with event log of old/new
- `setPin(pinHash)` — one-time PIN hash storage (hash computed off-chain), `verifyPin(pinHash)` to check
- `pauseContract()` / `unpauseContract()` — owner emergency stop
- Custom errors: `AlreadyRegistered`, `NotRegistered`, `UsernameTooLong`, `EmptyUsername`, `ZeroAddress`

### `TransactionTracker.sol`

Handles actual ETH transfers between registered wallets.

- `sendEth(to, gasPrice, gasLimit)` — payable, sends `msg.value` to `to`, logs a `Transaction` (SENT) for the sender and, if `to` is also registered, a mirrored `Transaction` (RECEIVED)
- Blocks self-transfers, zero-value sends, and calls while paused
- `getTransactions(wallet)`, `getMonthlyTransactions(wallet, start, end)`, `getWalletStats(wallet)` for querying
- `pauseContract()` / `UnpausedContract()` — owner controls

### `TrackerStorage.sol`

The analytics/history layer — richer records than `TransactionTracker`, priced in USD.

- `recordTransaction(wallet, to, amountWei, gasUsed, gasPrice, isSent)` — callable only by `s_authorizedTracker`, only for registered wallets. Converts amount + gas fee to USD via `PriceConverter`, stores a full `TxRecord`, and updates both monthly (`year → month → stats`) and lifetime aggregates
- `getAllTransactions(wallet)`, `getMonthlyStats(wallet, month, year)`, `getLifetimeStats(wallet)`, `getCurrentEthPrice()`
- `setAuthorizedTracker(address)` — owner-only wiring step run once after deploy

### `PriceConverter.sol` (library)

Wraps Chainlink `latestRoundData()` with guardrails:

- Reverts on stale price (`updatedAt == 0` or older than a 3-hour `TIMEOUT`)
- Reverts on zero or negative price
- Reverts on round mismatch (`answeredInRound < roundId`)
- `getEthUsdPrice`, `weiToUsd`, `usdToWei`, `calculateGasFeeWei`, `calculateGasFeeUsd`, plus decimals/description passthroughs

### `interfaces/AggregatorV3Interface.sol`

Standard Chainlink price feed interface (`decimals`, `description`, `version`, `getRoundData`, `latestRoundData`).

### `script/DeployWalletTracker.s.sol`

Foundry deployment script.

- `HelperConfig` picks the right ETH/USD price feed by `block.chainid` — Sepolia, Mainnet, or a locally-deployed `MockV3Aggregator` on Anvil (chain ID fallback)
- `DeployWalletTracker.run()` deploys `WalletRegistry` → `TransactionTracker` → `TrackerStorage`, then wires `TrackerStorage.setAuthorizedTracker(transactionTracker)` in the same broadcast

## Deployed Addresses

**Network:** Sepolia Testnet
**Chain ID:** `11155111`

| Contract             | Address                                      |
| -------------------- | -------------------------------------------- |
| `WalletRegistry`     | `0xb89b44DdCa766523b8b18FE375817c3598E3A2F7` |
| `TransactionTracker` | `0xF29B326347Ec8172502BEE1908E9Fed77A8C19c3` |
| `TrackerStorage`     | `0x57FC0141F9e43a656A3ED83762AC1884Fb231cea` |

## Project Structure

```
E-Transaction/
├── .github/               # CI workflows
├── broadcast/             # Forge deployment broadcast logs
├── cache/                 # Forge build cache
├── lib/                   # Forge dependencies (OpenZeppelin, forge-std, etc.)
├── out/                   # Compiled artifacts
├── script/
│   └── DeployWalletTracker.s.sol
├── src/
│   ├── interfaces/
│   │   └── AggregatorV3Interface.sol
│   ├── PriceConverter.sol
│   ├── TrackerStorage.sol
│   ├── TransactionTracker.sol
│   └── WalletRegistry.sol
├── test/
│   ├── PriceConverter.t.sol
│   ├── TrackerStorage.t.sol
│   ├── TransactionTracker.t.sol
│   └── WalletRegistry.t.sol
├── .env
├── .gitignore
├── .gitmodules
├── foundry.lock
├── foundry.toml
└── README.md
```

## Tech Stack

- **Solidity** `^0.8.20`
- **Foundry** (Forge + Anvil) for build, test, and deployment
- **OpenZeppelin Contracts** — `Ownable`, `ReentrancyGuard`, `Pausable`
- **Chainlink Price Feeds** — live ETH/USD pricing
- **Sepolia testnet** as primary deploy target

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`, `anvil`)
- Git

### Installation

```bash
git clone <repo-url>
cd E-Transaction
forge install
```

### Build

```bash
forge build --use 0.8.34
```

> Uses Solc `0.8.34` explicitly — plain `forge build` may pick a mismatched solc version.

## Testing

```bash
forge test
forge test -vvv          # verbose, shows traces on failure
forge test --match-contract WalletRegistryTest
forge coverage           # coverage report
```

Test suite covers all four contracts (`WalletRegistry`, `TransactionTracker`, `TrackerStorage`, `PriceConverter`) with unit tests for happy paths, revert conditions, event emissions, and fuzz tests for arbitrary amounts/gas prices/usernames.

## Deployment

```bash
forge script script/DeployWalletTracker.s.sol:DeployWalletTracker \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

The script auto-detects the network via `block.chainid`:
| Chain ID | Network | Price Feed |
|---|---|---|
| `11155111` | Sepolia | Chainlink ETH/USD (Sepolia) |
| `1` | Mainnet | Chainlink ETH/USD (Mainnet) |
| other | Anvil (local) | Freshly deployed `MockV3Aggregator` |

## Environment Variables

Create a `.env` file:

```env
PRIVATE_KEY=your_deployer_private_key
SEPOLIA_RPC_URL=your_sepolia_rpc_url
ETHERSCAN_API_KEY=your_etherscan_key   # for --verify
```

## License

MIT
