#!/usr/bin/env bash

# Ganache Local Accounts
#  - 1 = Contract Owner

deploy=
initialize=
networkName="local"
silent=

usage() {
    echo "usage: ./deploy.sh [-h] [-d | -i] [-n [local|ropsten|mainnet]]"
    echo "  -n | --network [local|kovan|mainnet]      Deploys contracts to the specified network (default is local)"
    echo "  -d | --deploy                             Run Contract Deployments"
    echo "  -i | --initialize                         Run Contract Initializations"
    echo "  -s | --silent                             Suppresses the Beep at the end of the script"
    echo "  -h | --help                               Displays this help screen"
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

runDeployments() {
    echoHeader
    echo "Deploying Token Contracts"
    echo " - using network: $networkName"

    echoHeader
    echo "Clearing previous build..."
    rm -rf build/

    echoHeader
    echo "Compiling Contracts.."
    truffle compile --all

    echoHeader
    echo "Running Contract Migrations.."
    truffle migrate --reset -f 1 --to 2 --network "$networkName"

    echoHeader
    echo "Contract Deployment Complete!"
    echo " "
    echoBeep
}

runInitializations() {
    echoHeader
    echo "Running Contract Initializations..."
    truffle migrate -f 3 --to 3 --network "$networkName"
    echoBeep
}


while [[ "$1" != "" ]]; do
    case $1 in
        -n | --network )        shift
                                networkName=$1
                                ;;
        -d | --deploy )         deploy="yes"
                                ;;
        -i | --initialize )     initialize="yes"
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

if [[ -n "$deploy" ]]; then
    runDeployments
elif [[ -n "$initialize" ]]; then
    runInitializations
else
    usage
fi
