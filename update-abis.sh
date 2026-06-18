#!/bin/bash
cd ~/E-transaction

for contract in WalletRegistry TransactionTracker TrackerStorage; do
  jq '.abi' "out/${contract}.sol/${contract}.json" > ~/e-frontend/src/contracts/${contract}.json
  jq '.abi' "out/${contract}.sol/${contract}.json" > ~/WalletTrackerIndexer/abis/${contract}.json
  echo "✅ ${contract} ABI updated"
done