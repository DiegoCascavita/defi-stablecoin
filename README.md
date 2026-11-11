# DeFi StableCoin (DSC)

Overcollateralized, DAI-style USD stablecoin with liquidations, Chainlink AggregatorV3 price feeds, and Foundry coverage (unit + fuzz + invariants).

**No UI and no Playwright in this repo.** Browser E2E belongs to portfolio project 3 (dApp). Manual testing here is Foundry + Anvil + `cast`.

Repo: [github.com/DiegoCascavita/defi-stablecoin](https://github.com/DiegoCascavita/defi-stablecoin)

---

## Cascade Suite

Chapter 1 of a related DeFi portfolio path — not a standalone tutorial island:

```text
defi-stablecoin  →  defi-lending  →  defi-dapp (Cascade Lend)
   DSC + HF            dual oracle        Next.js / wagmi
   liquidations        lending pool       Anvil demo UI
```

| Step | Repo | Role |
|---|---|---|
| 1 | **[defi-stablecoin](https://github.com/DiegoCascavita/defi-stablecoin)** (this repo) | Overcollateralized DSC, `OracleLib`, liquidations |
| 2 | **[defi-lending](https://github.com/DiegoCascavita/defi-lending)** | Dual-oracle lending market (DAI liquidity + WETH collateral) |
| 3 | **[defi-dapp](https://github.com/DiegoCascavita/defi-dapp)** | Cascade Lend UI on Anvil `31337` |

**GitHub pins (owner):** pin `defi-lending`, `defi-stablecoin`, and `defi-dapp` on [github.com/DiegoCascavita](https://github.com/DiegoCascavita) via *Customize your pins* — agents cannot change profile pins.

---

## Architecture

```
User
  │  deposit / mint / burn / redeem / liquidate
  ▼
┌─────────────┐      owns mint/burn      ┌──────────────────────────┐
│  DSCEngine  │ ◄─────────────────────── │ DecentralizedStableCoin │
│  (core)     │                          │ ERC20 "DSC"             │
└──────┬──────┘                          └──────────────────────────┘
       │ price
       ▼
┌──────────────────┐
│ Chainlink feed   │  Anvil: MockV3Aggregator
│ AggregatorV3     │  Sepolia: ETH/USD AggregatorV3 (HelperConfig stub)
└──────────────────┘
       ▲
Collateral: Anvil mock WETH · Sepolia WETH9 (Uniswap) via HelperConfig
```

| Piece | Role |
|---|---|
| `DecentralizedStableCoin` | Burnable ERC20; **only the Engine** may mint/burn |
| `DSCEngine` | Collateral deposit, mint/burn DSC, redeem, liquidations, health factor |
| `OracleLib` | Circuit breaker if the Chainlink price is stale (> 3 h) |
| `HelperConfig` + `DeployDSC` | Anvil mocks locally; Sepolia stub with Chainlink ETH/USD + WETH (no live broadcast in CI) |

### Solvency parameters

| Constant | Value | Meaning |
|---|---|---|
| Liquidation threshold | 50 | Need **200%** collateralization to mint |
| Min health factor | `1e18` | Below 1 → position is liquidatable |
| Liquidation bonus | 10% | Liquidator incentive |
| Peg | USD | Price via Chainlink feed (8 decimals) |

**Health factor** ≈ `(collateralUsd × 0.5) / dscMinted`

---

## Layout

```
src/
  DecentralizedStableCoin.sol
  DSCEngine.sol
  libraries/OracleLib.sol
script/
  DeployDSC.s.sol
  HelperConfig.s.sol
test/
  unit/          # DSC, Engine, OracleLib
  fuzz/          # Handler + invariants + fuzz helpers
  mocks/         # ERC20Mock, MockV3Aggregator
```

Forge libs: OpenZeppelin v5, chainlink-brownie-contracts, forge-std.

---

## How to run

### 1. Install Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
forge --version   # forge, cast, anvil
```

### 2. Clone, install deps, build, test

```bash
git clone https://github.com/DiegoCascavita/defi-stablecoin.git
cd defi-stablecoin
forge install
forge build
forge test
forge test -vv                 # invariant logs
forge test --gas-report
forge test --match-path 'test/fuzz/*' -vv
```

Fuzz / invariant knobs live in `foundry.toml` (`fuzz.runs = 256`, `invariant.runs = 128`, `depth = 64`).

### 3. Anvil + deploy script

```bash
# Terminal 1 — local chain
anvil

# Terminal 2 — broadcast deploy
forge script script/DeployDSC.s.sol:DeployDSC \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  -vvvv
```

The script deploys mock WETH + `MockV3Aggregator` ($2000/ETH), `DecentralizedStableCoin`, and `DSCEngine`, then transfers DSC ownership to the Engine.

Copy the printed addresses for the steps below (or parse `broadcast/.../run-latest.json`).

### 4. Manual mint / deposit flow with `cast`

Use Anvil account #0 (default key shown by `anvil`). Replace placeholders with addresses from the deploy.

```bash
export RPC=http://127.0.0.1:8545
export PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export USER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export WETH=<weth_address>
export ENGINE=<engine_address>
export DSC=<dsc_address>
export FEED=<price_feed_address>

# Mint mock WETH to yourself (ERC20Mock.mint)
cast send "$WETH" "mint(address,uint256)" "$USER" 10000000000000000000 \
  --rpc-url "$RPC" --private-key "$PK"

# Approve Engine to pull collateral
cast send "$WETH" "approve(address,uint256)" "$ENGINE" 10000000000000000000 \
  --rpc-url "$RPC" --private-key "$PK"

# Deposit 10 WETH
cast send "$ENGINE" "depositCollateral(address,uint256)" "$WETH" 10000000000000000000 \
  --rpc-url "$RPC" --private-key "$PK"

# Mint 100 DSC (1e20 wei) — well under 200% CR at $2000/ETH
cast send "$ENGINE" "mintDsc(uint256)" 100000000000000000000 \
  --rpc-url "$RPC" --private-key "$PK"

# Check balances / health
cast call "$DSC" "balanceOf(address)(uint256)" "$USER" --rpc-url "$RPC"
cast call "$ENGINE" "getHealthFactor(address)(uint256)" "$USER" --rpc-url "$RPC"

# Optional: crash ETH price to force HF < 1, then liquidate from another account
cast send "$FEED" "updateAnswer(int256)" 1800000000 \
  --rpc-url "$RPC" --private-key "$PK"
```

Burn / redeem / liquidate follow the same pattern (`burnDsc`, `redeemCollateral`, `liquidate`).

---

## Sepolia stub (no live deploy from CI)

`HelperConfig` selects config by `block.chainid`:

| Chain | `chainid` | WETH | ETH/USD feed |
|---|---|---|---|
| Anvil | `31337` | `ERC20Mock` (deployed) | `MockV3Aggregator` @ $2000 |
| Sepolia | `11155111` | [`0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14`](https://sepolia.etherscan.io/address/0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14) (WETH9) | [`0x694AA1769357215DE4FAC081bf1f309aDC325306`](https://sepolia.etherscan.io/address/0x694AA1769357215DE4FAC081bf1f309aDC325306) (Chainlink) |

Sepolia path **does not** deploy mocks and **does not** broadcast by itself. Owner-only example (secrets in a local gitignored `.env` — never paste keys into chat):

```bash
# .env (gitignored): SEPOLIA_RPC_URL, PRIVATE_KEY, ETHERSCAN_API_KEY
source .env
forge script script/DeployDSC.s.sol:DeployDSC \
  --rpc-url "$SEPOLIA_RPC_URL" --broadcast --verify -vvvv
```

After a real deploy, confirm `dsc.owner() == engine` on Sepolia Etherscan. Collateral on Sepolia is real WETH (wrap ETH) — there is no Anvil-style `mint` faucet.

---

## Features

- Deposit allowlisted ERC20 collateral (mock WETH on Anvil; Sepolia WETH stubbed)
- Mint DSC against collateral (health factor enforced)
- Burn DSC and redeem collateral
- Liquidate under-collateralized positions (10% bonus)
- AggregatorV3 oracle + `OracleLib` stale-price revert
- Anvil deploy scripts + mocks; Sepolia feed/WETH addresses in `HelperConfig`
- Unit, fuzz, and solvency invariant tests

---

## Threat model (auditor notes)

| Risk | Current mitigation | Residual |
|---|---|---|
| **Reentrancy** on deposit/redeem/liquidate | `ReentrancyGuard` + CEI | Exotic ERC777/callback tokens |
| **Oracle stale / freeze** | `OracleLib` 3h timeout | No TWAP fallback; dead feed halts pricing |
| **Oracle manipulation** | Mainnet relies on Chainlink heartbeats / L2 sequencer assumptions | Anvil mock is fully trusted; no on-chain defense against mock admin |
| **Access control** | Only Engine (DSC owner) mints/burns | Engine mint bug would inflate supply |
| **Liquidation griefing / bad debt** | 10% bonus + partial liquidations | Sharp price crash can leave bad debt without liquidators |
| **Precision / rounding** | 8 → 18 decimals via `ADDITIONAL_FEED_PRECISION` | Dust edge cases |
| **Centralization** | DSC ownership transferred to Engine at deploy | Deployer must verify `transferOwnership` |

Key invariant covered in tests: **USD value of collateral held by the Engine ≥ `dsc.totalSupply()`** (Handler does not crash the oracle price).

---

## Slither (optional)

```bash
pip install slither-analyzer
slither . --filter-paths "lib|test|script"

# Or Docker
docker run -v "$PWD":/app trailofbits/eth-security-toolbox
# inside:
cd /app && slither . --filter-paths "lib|test|script"
```

Interpret `arbitrary-send`, `reentrancy-eth`, `timestamp`, and `divide-before-multiply` in context — several are informational for an overcollateralized design.

---

## Cómo probar (resumen)

1. Instalar Foundry (`foundryup`), luego `forge install && forge build && forge test`.
2. En una terminal: `anvil`. En otra: `forge script script/DeployDSC.s.sol:DeployDSC --rpc-url http://127.0.0.1:8545 --broadcast -vvvv`.
3. Con `cast`: mint WETH mock → `approve` → `depositCollateral` → `mintDsc`. Opcional: bajar el precio del feed y llamar `liquidate`.
4. **No hay UI ni Playwright aquí** — eso va en el proyecto dApp.

---

## License

MIT
