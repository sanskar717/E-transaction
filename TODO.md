# TrackerStorage.sol Production Fix TODO

## [ ] Step 1: Fix compilation error in weiToUsd call

- Change `PriceConverter.weiToUsd(i_priceFeed, _amountWei)` → `i_priceFeed.weiToUsd(_amountWei)`

## [ ] Step 2: Complete recordTransaction function

- Calculate gasFeeWei and gasFeeUsd using PriceConverter helpers
- Extract month/year from timestamp
- Create and store TxRecord
- Update monthly stats mapping
- Update cumulative totals (ethSent/Received/gasFees)
- Emit events

## [ ] Step 3: Test compilation

- Run `forge build`

## [ ] Step 4: Add unit tests (optional)

- Test recordTransaction end-to-end

## [ ] Step 5: Production verification

- Verify Chainlink integration
- Gas optimization review
