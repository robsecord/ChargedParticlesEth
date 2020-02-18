#!/usr/bin/env bash

# Parse env vars from .env file
export $(egrep -v '^#' .env | xargs)

ownerAccount=
networkName="development"
verbose=
silent=
update=

usage() {
    echo "usage: ./deploy.sh [[-n [development|kovan|mainnet] [-f] [-v]] | [-h]]"
    echo "  -n    | --network [development|kovan|mainnet]  Deploys contracts to the specified network (default is local)"
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

deployFresh() {
    if [[ "$networkName" == "development" ]]; then
        ownerAccount=$(npx oz accounts -n ${networkName} --no-interactive 2>&1 | head -n 9 | tail -n 1) # Get Account 3
        ownerAccount="${ownerAccount:(-42)}"

        echoHeader
        echo "Clearing previous build..."
        rm -rf build/

        echo "Compiling contracts.."
        npx oz compile
    elif [[ "$networkName" == "kovan" ]]; then
        ownerAccount="$KOVAN_OWNER_ADDRESS"
    elif [[ "$networkName" == "ropsten" ]]; then
        ownerAccount="$ROPSTEN_OWNER_ADDRESS"
    elif [[ "$networkName" == "mainnet" ]]; then
        ownerAccount="$MAINNET_OWNER_ADDRESS"
    fi

    echo " "
    echo "Using Owner Account \"$ownerAccount\" on $networkName"
    echo " "

    echoHeader
    echo "Creating Contract: ChaiNucleus"
    addressChaiNucleus=$(npx oz create ChaiNucleus -n ${networkName} --no-interactive | tail -n 1)
    sleep 1s

    echoHeader
    echo "Creating Contract: ChargedParticlesEscrow"
    addressChargedParticlesEscrow=$(npx oz create ChargedParticlesEscrow -n ${networkName} --init initialize --args ${ownerAccount} --no-interactive | tail -n 1)
    sleep 1s

    echoHeader
    echo "Creating Contract: ChargedParticles"
    addressChargedParticles=$(npx oz create ChargedParticles -n ${networkName} --init initialize --args ${ownerAccount} --no-interactive | tail -n 1)
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

deployUpdate() {
    echoHeader
    echo "Pushing Contract Updates to network \"$networkName\".."

    npx oz upgrade --all --no-interactive -n ${networkName}

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

if [[ -n "$update" ]]; then
    deployUpdate
else
    deployFresh
fi

