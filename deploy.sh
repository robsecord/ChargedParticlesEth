#!/usr/bin/env bash

# Parse env vars from .env file
export $(egrep -v '^#' .env | xargs)

ownerAccount=
networkName="development"
silent=
init=
update=


addrChaiNucleus=
addrChargedParticles=
addrChargedParticlesEscrow=
addrChargedParticlesERC1155=

depositFee="50000000000000000000"
assetPair="chai"
daiAddress="0xa31362CEa1B5CafE8C0F0b22eB64d4444d5249c8"
daiPrefund="10000000000000000000"
ethFee="1100000000000000"
ionFee="1000000000000000000"
ionUrl="https://ipfs.io/ipfs/QmbNDYSzPUuEKa8ppv1W11fVJVZdGBUku2ZDKBqmUmyQdT"
ionSupply="2000000000000000000000000"
ionMint="1000000000000000000000000"   # reserves
ionPrice="750000000000000"

# ETH Fee:
#      NFT:    $0.25   or  2 IONs
#       FT:    $0.15   or  1 ION
#      ION:    $0.10

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
    oz balance --from "$ownerAccount" -n "$networkName" --no-interactive
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
    addrChaiNucleus=$(oz create ChaiNucleus --init initRopsten --no-interactive | tail -n 1)
    sleep 1s

    echoHeader
    echo "Creating Contract: ChargedParticles"
    oz add ChargedParticles --push --skip-compile
    addrChargedParticles=$(oz create ChargedParticles --init initialize --args ${ownerAccount} --no-interactive | tail -n 1)
    sleep 1s

    echoHeader
    echo "Creating Contract: ChargedParticlesEscrow"
    oz add ChargedParticlesEscrow --push --skip-compile
    addrChargedParticlesEscrow=$(oz create ChargedParticlesEscrow --init initialize --args ${ownerAccount} --no-interactive | tail -n 1)
    sleep 1s

    echoHeader
    echo "Creating Contract: ChargedParticlesERC1155"
    oz add ChargedParticlesERC1155 --push --skip-compile
    addrChargedParticlesERC1155=$(oz create ChargedParticlesERC1155 --init initialize --args ${ownerAccount} --no-interactive | tail -n 1)
    sleep 1s

    echoHeader
    echo "Contracts deployed.."

#    echoHeader
#    echo "Pre-funding owner with Asset Tokens.."

#    echo " "
#    echo "Pre-fund DAI: $daiPrefund"
#    result=$(oz send-tx --no-interactive --to ${daiAddress} --method 'mint' --args ${ownerAccount},${daiPrefund})

    echoHeader
    echo "Initializing ChargedParticlesERC1155.."

    echo " "
    echo "setChargedParticles: $addrChargedParticles"
    result=$(oz send-tx --no-interactive --to ${addrChargedParticlesERC1155} --method 'setChargedParticles' --args ${addrChargedParticles})

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
    echo "registerTokenManager: $addrChargedParticlesERC1155"
    result=$(oz send-tx --no-interactive --to ${addrChargedParticles} --method 'registerTokenManager' --args ${addrChargedParticlesERC1155})

    echo " "
    echo "registerAssetPair: $assetPair"
    result=$(oz send-tx --no-interactive --to ${addrChargedParticles} --method 'registerAssetPair' --args ${assetPair})

#    # Convert ION URL to Hex
#    ionUrl=$(xxd -pu <<< "$ionUrl")
#    ionUrl="0x$ionUrl"
#    echo " "
#    echo "mintIons: "
#    echo " - ionUrl: $ionUrl"
#    echo " - ionSupply: $ionSupply"
#    echo " - ionMint: $ionMint"
#    echo " - ionPrice: $ionPrice"
#    result=$(oz send-tx --no-interactive --to ${addrChargedParticles} --method 'mintIons' --args ${ionUrl},${ionSupply},${ionMint},${ionPrice})

    echoHeader
    echo " "
    echo "MANUAL TODO:"
    echo "   oz send-tx -n $networkName --to $addrChargedParticles"
    echo "    - mintIons: $ionUrl $ionSupply $ionMint $ionPrice"

    echoHeader
    echo "Contracts initialized.."
    echo " "

    echoHeader
    echo "Contract Addresses: "
    echo " - ChaiNucleus:             $addrChaiNucleus"
    echo " - ChargedParticles:        $addrChargedParticles"
    echo " - ChargedParticlesEscrow:  $addrChargedParticlesEscrow"
    echo " - ChargedParticlesERC1155: $addrChargedParticlesERC1155"

    echoHeader
    echo "Contract Deployment & Initialization Complete!"
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

if [[ -n "$update" ]]; then
    deployUpdate
else
    deployFresh
fi

