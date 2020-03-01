#!/usr/bin/env bash

# Parse env vars from .env file
export $(egrep -v '^#' .env | xargs)

ownerAccount=
networkName="development"
verbose=
silent=
init=
update=


addrChaiNucleus="0x0941C8B530230884fc6dd9d12EB68fE36824f0BE"
addrChargedParticles="0x9E243ACE864FD8061F07faA484F35c8732378294"
addrChargedParticlesEscrow="0x2235B33e1bdAfE5f929a42475fe1F785DA657280"

depositFee="50000000000000000000"
assetPair="chai"
daiAddress="0x8B7f1E7F3412331F1Cd317EAE5040DfE5eaAdAe6"
ethFee="380000000000000"
ionFee="1000000000000000000"
ionUrl="https://ipfs.io/ipfs/QmQ98oeXhZRVEMuo5gyYCLF5kmaqhsGPFUPm4WrMVJuJ5c"
ionSupply="2000000000000000000000000"
ionMint="1000000000000000000000000"
ionPrice="570000000000000"


usage() {
    echo "usage: ./deploy.sh [[-n [development|kovan|mainnet] [-f] [-v]] | [-h]]"
    echo "  -n    | --network [development|kovan|mainnet]  Deploys contracts to the specified network (default is local)"
    echo "  -i    | --init                                 Initialize contracts after deployment"
    echo "  -u    | --update                               Push updates to deployments"
    echo "  -v    | --verbose                              Outputs verbose logging"
    echo "  -s    | --silent                               Suppresses the Beep at the end of the script"
    echo "  -h    | --help                                 Displays this help screen"
}

echoHeader() {
    echo " "
    echo "-----------------------------------------------------------"
    echo "-----------------------------------------------------------"
}

echoBeep() {
    [[ -z "$silent" ]] && {
        afplay /System/Library/Sounds/Glass.aiff
    }
}

getOwnerAccount() {
    if [[ "$networkName" == "development" ]]; then
        ownerAccount=$(oz accounts -n ${networkName} --no-interactive 2>&1 | head -n 9 | tail -n 1) # Get Account 3
        ownerAccount="${ownerAccount:(-42)}"
    elif [[ "$networkName" == "kovan" ]]; then
        ownerAccount="$KOVAN_OWNER_ADDRESS"
    elif [[ "$networkName" == "ropsten" ]]; then
        ownerAccount="$ROPSTEN_OWNER_ADDRESS"
    elif [[ "$networkName" == "mainnet" ]]; then
        ownerAccount="$MAINNET_OWNER_ADDRESS"
    fi

    oz session --no-interactive --from "$ownerAccount" -n "$networkName"
}

deployFresh() {
    getOwnerAccount

    if [[ "$networkName" == "development" ]]; then
        echoHeader
        echo "Clearing previous build..."
        rm -rf build/
        rm -f "./.openzeppelin/$networkName.json"

        echo "Compiling contracts.."
        oz compile
    fi

    echoHeader
    echo "Creating Contract: ChaiNucleus"
    addressChaiNucleus=$(oz create ChaiNucleus --init initRopsten --no-interactive | tail -n 1)
    sleep 1s

    echoHeader
    echo "Creating Contract: ChargedParticlesEscrow"
    addressChargedParticlesEscrow=$(oz create ChargedParticlesEscrow --init initialize --args ${ownerAccount} --no-interactive | tail -n 1)
    sleep 1s

    echoHeader
    echo "Creating Contract: ChargedParticles"
    addressChargedParticles=$(oz create ChargedParticles --init initialize --args ${ownerAccount} --no-interactive | tail -n 1)
    sleep 1s

    echoHeader
    echo "Contract Addresses: "
    echo " - ChaiNucleus:            $addressChaiNucleus"
    echo " - ChargedParticlesEscrow: $addressChargedParticlesEscrow"
    echo " - ChargedParticles:       $addressChargedParticles"

    echoHeader
    echo "Contract Deployment Complete!"
    echo " "
    echoBeep
}

initialize() {
    getOwnerAccount

    echoHeader
    echo "Initializing ChargedParticlesEscrow.."

    echo " "
    echo "setDepositFee: $depositFee"
    result=$(oz send-tx --no-interactive --to ${addrChargedParticlesEscrow} --method 'setDepositFee' --args ${depositFee})

    echo " "
    echo "registerChargedParticles: $addrChargedParticles"
    result=$(oz send-tx --no-interactive --to ${addrChargedParticlesEscrow} --method 'registerChargedParticles' --args ${addrChargedParticles})

    echo " "
    echo "registerAssetPair: $assetPair, $daiAddress, $addrChaiNucleus"
    result=$(oz send-tx --no-interactive --to ${addrChargedParticlesEscrow} --method 'registerAssetPair' --args ${assetPair},${daiAddress},${addrChaiNucleus})

    echoHeader
    echo "Initializing ChargedParticles.."

    echo " "
    echo "setupFees: $ethFee, $ionFee"
    result=$(oz send-tx --no-interactive --to ${addrChargedParticles} --method 'setupFees' --args ${ethFee},${ionFee})

    echo " "
    echo "registerEscrow: $addrChargedParticlesEscrow"
    result=$(oz send-tx --no-interactive --to ${addrChargedParticles} --method 'registerEscrow' --args ${addrChargedParticlesEscrow})

    echo " "
    echo "registerAssetPair: $assetPair"
    result=$(oz send-tx --no-interactive --to ${addrChargedParticles} --method 'registerAssetPair' --args ${assetPair})

    echoHeader
    echo " "
    echo "MANUAL TODO:"
    echo "   oz send-tx -n $networkName --to $addrChargedParticles"
    echo "    - mintIons: $ionUrl $ionSupply $ionMint $ionPrice"
#    result=$(oz send-tx --no-interactive --to ${addrChargedParticles} --method 'mintIons' --args ${ionUrl},${ionSupply},${ionMint},${ionPrice})

    echoHeader
    echo "Contract Initialization Complete!"
    echo " "
    echoBeep
}

deployUpdate() {
    getOwnerAccount

    echoHeader
    echo "Pushing Contract Updates to network \"$networkName\".."

    oz upgrade --all --no-interactive

    echo " "
    echo "Contract Updates Complete!"
    echo " "
    echoBeep
}


while [[ "$1" != "" ]]; do
    case $1 in
        -n | --network )        shift
                                networkName=$1
                                ;;
        -i | --init )           init="yes"
                                ;;
        -u | --update )         update="yes"
                                ;;
        -v | --verbose )        verbose="yes"
                                ;;
        -s | --silent )         silent="yes"
                                ;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done

if [[ -n "$init" ]]; then
    initialize
elif [[ -n "$update" ]]; then
    deployUpdate
else
    deployFresh
fi

