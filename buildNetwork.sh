#!/bin/bash
BROWN='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
LBLUE='\033[1;34m'
NC='\033[0m'
GREEN='\033[0;32m'
echo $@

ORG_NAME="$1"
CHANNEL_NAME="$2"
P_CNT=$3
CC_NAME="$4"
CC_VERSION="$5"
CC_SRC_PATH="$6"
DELAY="3"
TIMEOUT="10"
COUNTER=1
MAX_RETRY=3
INS_RETRY=3
CCR=1
LANGUAGE="golang"
ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer0.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
echo -e "${GREEN}"
echo "Building ${CHANNEL_NAME} channel and adding An Organisation"
echo -e "${NC}"

setGlobals () {
	PEER=$1
    CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/${ORG_NAME}.example.com/peers/peer0.${ORG_NAME}.example.com/tls/ca.crt
	CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/${ORG_NAME}.example.com/users/Admin@${ORG_NAME}.example.com/msp
    CORE_PEER_ADDRESS=peer${PEER}.$ORG_NAME.example.com:7051
}

# verify the results
verifyResult () {
	if [ $1 -ne 0 ] ; then
		echo -e "${RED}!!!!!!!!!!!!!!! "$2" !!!!!!!!!!!!!!!!"
        echo "========= ERROR !!! FAILED to execute ==========="
		echo -e "${NC}"
   		exit 1
	fi
}
verifyChannelCreation () {
    if [ $1 -ne 0 -a $CCR -lt 2 ] ; then
        echo -e "${BROWN}"
        sleep 10
        CCR=` expr $CCR + 2`
        COUNTER=1
        createChannelWithRetry
        elif [ $CCR -eq 2 ]; then
            echo "Channel Creation failed ....."
            exit 1        
    fi
}
joinChannelWithRetry () {
    setGlobals $1
    set -x
	peer channel join -b $CHANNEL_NAME.block  >&log.txt
	res=$?
    set +x
	cat log.txt
	if [ $res -ne 0 -a $COUNTER -lt $MAX_RETRY ]; then
		COUNTER=` expr $COUNTER + 1`
		echo "peer${PEER}.${ORG_NAME}.exapmle.com failed to join the channel, Retry after $DELAY seconds"
		sleep $DELAY
		joinChannelWithRetry $peer 
        return
	else
		COUNTER=1
	fi
	verifyResult $res "After $MAX_RETRY attempts, peer${peer}.${ORG_NAME}.exapmle.com has failed to Join the Channel"
}
createChannelWithRetry () {
    setGlobals 0
    set -x
    peer channel create -o orderer0.example.com:7050 -c $CHANNEL_NAME -f ./$CHANNEL_NAME.tx --tls --cafile $ORDERER_CA >log.tx
    res=$?
    set -x
    cat log.tx
    if [ $res -ne 0 -a $COUNTER -lt $MAX_RETRY ]; then
		COUNTER=` expr $COUNTER + 1`
		echo "peer${PEER}.${ORG_NAME}.exapmle.com failed to create channel, Retry after $DELAY seconds"
		sleep $DELAY
		createChannelWithRetry 0 
        return
	else
		COUNTER=1
	fi
    verifyChannelCreation $res 
    echo "===================== Channel \"$CHANNEL_NAME\" is created successfully ===================== "
    echo
}
updateAnchorWithRetry () {
    setGlobals $1
    set -x
    peer channel update -o orderer0.example.com:7050 -c $CHANNEL_NAME -f ./${ORG_NAME}MSPanchors.tx --tls --cafile $ORDERER_CA >log.tx
    res=$?
    set -x
    cat log.tx
    if [ $res -ne 0 -a $COUNTER -lt $MAX_RETRY ]; then
		COUNTER=` expr $COUNTER + 1`
		echo "peer${peer}.${ORG_NAME}.exapmle.com failed to update anchor Peer, Retry after $DELAY seconds"
		sleep $DELAY
		updateAnchorWithRetry $peer 
        return
	else
		COUNTER=1
	fi
    verifyResult $res "peer${peer}.${ORG_NAME}.exapmle.com failed to update anchor Peer"
    echo "===================== peer${peer}.${ORG_NAME}.exapmle.com updated anchor Peer successfully ===================== "
    echo
}

installChaincodeWithRetry () {
    setGlobals $1 
    set -x
	peer chaincode install -n ${CC_NAME} -v ${CC_VERSION} -l ${LANGUAGE} -p ${CC_SRC_PATH} >&log.txt
	res=$?
    set +x
	cat log.txt
    if [ $res -ne 0 -a $COUNTER -lt $MAX_RETRY ]; then
		COUNTER=` expr $COUNTER + 1`
		echo "Chaincode installation on peer${peer}.${ORG_NAME}.exapmle.com has Failed, Retry after $DELAY seconds"
		sleep $DELAY
		installChaincodeWithRetry $peer 
        return
	else
		COUNTER=1
	fi
	verifyResult $res "Chaincode installation on peer${peer}.${ORG_NAME}.exapmle.com has Failed"
	echo "===================== Chaincode is installed on peer${peer}.${ORG_NAME}.exapmle.com ===================== "
	echo
}
instantiatedWithRetry () {
    setGlobals $1 
    set -x
    peer chaincode instantiate -o orderer0.example.com:7050 --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n ${CC_NAME} -v ${CC_VERSION} -c '{"Args":["init","a", "100", "b","200"]}'
    res=$?
    set +x
    cat log.txt
    if [ $res -ne 0 -a $COUNTER -lt $INS_RETRY ]; then
		COUNTER=` expr $COUNTER + 1`
		echo "Chaincode instantiation on peer0.${ORG_NAME}.exapmle.com on channel '$CHANNEL_NAME' failed, Retry after $DELAY seconds"
		sleep $DELAY
		instantiatedWithRetry $1
        return
	else
		COUNTER=1
	fi
    verifyResult $res "Chaincode instantiation on peer0.${ORG_NAME}.exapmle.com on channel '$CHANNEL_NAME' failed"
    echo "===================== Chaincode Instantiation on peer0.${ORG_NAME}.exapmle.com on channel '$CHANNEL_NAME' is successful ===================== "
    echo
}
chainQuery () {
    sleep 10
    set -x
    peer chaincode query -C $CHANNEL_NAME -n ${CC_NAME} -c '{"Args":["query","a"]}' >&log.txt
    res=$?
    set +x
    cat log.txt
    EXPECTED_RESULT=100
    if [ $res -ne 0 -a $COUNTER -lt $INS_RETRY ]; then
		COUNTER=` expr $COUNTER + 1`
		echo -e "${RED}Chaincode query on channel '$CHANNEL_NAME' failed, Retry after $DELAY seconds${NC}"
		sleep $DELAY
		chainQuery
        return
    else
        COUNTER=1
    fi
    if [ $res -eq 0 ]; then
        VALUE=$(cat log.txt)
        if [ "$VALUE" == "$EXPECTED_RESULT" ]; then
            echo -e "${GREEN}"
            echo "======= Expected value  -  Returned Value =========="
            echo "======= ${EXPECTED_RESULT}             -  ${VALUE}            =========="
            echo
            echo -e "======= SUCCESFULLY INSTANTIATED CHAINCODE ON  CHANNEL ${CHANNEL_NAME} ==========${NC}"
            exit 0
        else
            echo -e "${RED}Expected ${EXPECTED_RESULT} but got ${VALUE}"
            echo "!!!!!!!!!!... FAILED...!!!!!!!!!!${NC}"
            exit 1
        fi
    fi
}

sleep 30

# Channel creation 
echo -e "${GREEN}"
echo "========== Channel ${CHANNEL_NAME} creation started =========="
echo -e "${NC}"
#sleep 5
sleep 10
createChannelWithRetry

# Join Channel
echo -e "${GREEN}"
echo "========== Peers  Joining channel started =========="
echo -e "${NC}"
peer=0
while [ "$peer" != "$P_CNT" ]
do
    joinChannelWithRetry $peer 
    echo "===================== peer${peer}.${ORG_NAME}.exapmle.com joined on the channel \"$CHANNEL_NAME\" ===================== "
    sleep $DELAY
    echo
    peer=$(expr $peer + 1)
done

# Update Anchor peer 
echo -e "${GREEN}"
echo "========== Updating Anchor peer ========="
echo -e "${NC}"
#sleep 10
updateAnchorWithRetry 0

# Chaincode installation
echo -e "${GREEN}"
echo "========== Chaincode installation started ========== "
echo -e "${NC}"
peer=0
while [ "$peer" != "$P_CNT" ]
do
    #sleep 10
    installChaincodeWithRetry $peer 
    sleep $DELAY
    echo
    peer=$(expr $peer + 1)
done

# INSTANTIATION
echo -e "${GREEN}"
echo "========== Instantiation on ${CHANNEL_NAME} STARTED ========="
echo -e "${NC}"
sleep 5
instantiatedWithRetry 0
sleep 20

# Query 
echo -e "${GREEN}"
echo "========== Attempting to Query peer0.${ORG_NAME}.exapmle.com ...$(($(date +%s)-starttime)) secs =========="
echo -e "${NC}"
chainQuery