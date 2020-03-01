#!/usr/bin/env bash

# NOTE: Install "jq"
# brew install jq

requireFields='{fileName: .fileName, contractName: .contractName, abi: .abi, compiler: .compiler, networks: .networks}'

rm -f ./ChargedParticles.json
rm -f ./ChargedParticlesEscrow.json

echo "Generating JSON file for ChargedParticles"
cat ./build/contracts/ChargedParticles.json | jq -r "$requireFields" > ./ChargedParticles.json

echo "Generating JSON file for ChargedParticlesEscrow"
cat ./build/contracts/ChargedParticlesEscrow.json | jq -r "$requireFields" > ./ChargedParticlesEscrow.json


