#!/usr/bin/env bash

# Parse env vars from .env file
export $(egrep -v '^#' .env | xargs)

ownerAccount=
networkName="development"
silent=
init=
update=


addrChaiNucleus="0x6D458E5a64F04BFDCd6560B9Ce44213D901FB9F2"
addrChargedParticles="0x94EA50510C391C3D068AD4f1c83fb0203d305E17"
addrChargedParticlesEscrow="0x2b8fB0804fFFd1F944a28bF12161d6b8b9043E85"

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
    echo "usage: ./deploy.sh [[-n [development|kovan|mainnet] [-i] [-u] [-v] [-s]] | [-h]]"
    echo "  -n    | --network [development|kovan|mainnet]  Deploys contracts to the specified network (default is local)"
    echo "  -i    | --init                                 Initialize contracts after deployment"
    echo "  -u    | --update                               Push updates to deployments"
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
    oz balance --from "$ownerAccount" -n "$networkName" --no-interactives
    oz balance --no-interactive --from "$ownerAccount" -n "$networkName" --erc20 "$daiAddress"
}

deployFresh() {
    getOwnerAccount

    if [[ "$networkName" != "mainnet" ]]; then
        echoHeader
        echo "Clearing previous build..."
        rm -rf build/
        rm -f "./.openzeppelin/$networkName.json"
    fi

    echo "Compiling contracts.."
    oz compile

    echoHeader
    echo "Creating Contract: ChaiNucleus"
    oz add ChaiNucleus --push --skip-compile
    addressChaiNucleus=$(oz create ChaiNucleus --init initRopsten --no-interactive | tail -n 1)
    sleep 1s

    echoHeader
    echo "Creating Contract: ChargedParticlesEscrow"
    oz add ChargedParticlesEscrow --push --skip-compile
    addressChargedParticlesEscrow=$(oz create ChargedParticlesEscrow --init initialize --args ${ownerAccount} --no-interactive | tail -n 1)
    sleep 1s

    echoHeader
    echo "Creating Contract: ChargedParticles"
    oz add ChargedParticles --push --skip-compile
    addressChargedParticles=$(oz create ChargedParticles --init initialize --args ${ownerAccount} --no-interactive | tail -n 1)
    sleep 1s

    echoHeader
    echo "Contract Addresses: "
    echo " - ChaiNucleus:            $addressChaiNucleus"
    echo " - ChargedParticles:       $addressChargedParticles"
    echo " - ChargedParticlesEscrow: $addressChargedParticlesEscrow"

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

