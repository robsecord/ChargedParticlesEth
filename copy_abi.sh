#!/usr/bin/env bash

# NOTE: Install "jq"
# brew install jq

requireFields='{fileName: .fileName, contractName: .contractName, abi: .abi, compiler: .compiler, networks: .networks}'

rm -f ./ChargedParticles.json
rm -f ./ChargedParticlesEscrowManager.json
rm -f ./ChargedParticlesTokenManager.json

echo "Generating JSON file for ChargedParticles"
cat ./build/contracts/ChargedParticles.json | jq -r "$requireFields" > ./ChargedParticles.json

echo "Generating JSON file for ChargedParticlesEscrowManager"
cat ./build/contracts/ChargedParticlesEscrowManager.json | jq -r "$requireFields" > ./ChargedParticlesEscrowManager.json

echo "Generating JSON file for ChargedParticlesTokenManager"
cat ./build/contracts/ChargedParticlesTokenManager.json | jq -r "$requireFields" > ./ChargedParticlesTokenManager.json


