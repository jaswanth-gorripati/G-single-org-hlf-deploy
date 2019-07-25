#!/bin/bash

. ./env.sh
. ./teardownNetwork.sh

ARCH=`uname -s | grep Darwin`
if [ "$ARCH" == "Darwin" ]; then
OPTS="-it"
else
OPTS="-i"
fi
CLI_CNTR=""

function startNetwork() {
  if [ "${1}" == "remove" ];then
    removeNetwork
  else
    removeNetwork
    genFiles
    runNetworkSetup
  fi
}

function genFiles() {
    cd ./tempFiles/
    CONFIGTX_FILE="temp-configtx.yaml"
    CRYPTO_CONFIG_FILE="temp-crypto-config.yaml"
    DOCKER_FILE="temp-docker-compose.yaml"
    sed -e "s/{ORGANISATION_NAME}/${ORG_NAME}/g" -e "s/CHANNEL_NAME/${CHANNEL_NAME}/g" $CONFIGTX_FILE > ../configtx.yaml
    sed -e "s/ORGANISATION_NAME/${ORG_NAME}/g" $CRYPTO_CONFIG_FILE > ../crypto-config.yaml
    sed -e "s/{ORGANISATION_NAME}/${ORG_NAME}/g" -e "s/NETWORK_NAME/${NETWORK_NAME}/g" $DOCKER_FILE > ../docker-compose.yaml
    cd ../
}

function runNetworkSetup() {
    genCrypto
    genConfigFiles
    replaceCAkey
    dockerNetworkSetup
}

function genCrypto() {
  export PATH=./bin:./bin:$PATH
  export FABRIC_CFG_PATH=./
  which cryptogen
  if [ "$?" -ne 0 ]; then
    echo -e  "${RED}cryptogen tool not found. exiting${NC}"
    exit 1
  fi
  echo -e "${GREEN}"
  echo "##########################################################"
  echo "##### Generate certificates using cryptogen tool #########"
  echo "##########################################################"
  echo -e "${NC}"
  if [ -d "crypto-config" ]; then
    rm -Rf crypto-config
  fi
  ARCH=`uname -s | grep Darwin`
  if [ "$ARCH" == "Darwin" ]; then
    OPTS="-it"
  else
    OPTS="-i"
  fi

  CRYPTO_CONFIG_FILE="crypto-config.yaml"
  cryptogen generate --config=./${CRYPTO_CONFIG_FILE}
  if [ "$?" -ne 0 ]; then
    echo -e "${RED}Failed to generate certificates...${NC}"
    exit 1
  fi
}

function genConfigFiles() {
  which configtxgen
  if [ "$?" -ne 0 ]; then
    echo -e "${RED}configtxgen tool not found. exiting${NC}"
    exit 1
  fi

  if [ -f "channel.tx" ]; then
    rm ${ORG_NAME}.tx genesis.block ${ORG_NAME}MSPanchors.tx
  fi

  CONFIGTX_FILE="configtx.yaml"
  echo -e "${GREEN}"
  echo "##########################################################"
  echo "#########  Generating Orderer Genesis block ##############"
  echo "##########################################################"
  echo -e "${NC}"
   configtxgen -profile SoloOrdererProfile -outputBlock ./genesis.block
  if [ "$?" -ne 0 ]; then
    echo -e "${RED}Failed to generate orderer genesis block...${NC}"
    exit 1
  fi
  echo -e "${GREEN}"
  echo "#########################################################################"
  echo "### Generating channel configuration transaction for '${CHANNEL_NAME}' ###"
  echo "#########################################################################"
  echo -e "${NC}"
   configtxgen -profile ${CHANNEL_NAME} -outputCreateChannelTx ./${CHANNEL_NAME}.tx -channelID ${CHANNEL_NAME}
  if [ "$?" -ne 0 ]; then
    echo -e "${RED}Failed to generate channel configuration transaction...${NC}"
    exit 1
  fi

   configtxgen -profile ${CHANNEL_NAME} -outputAnchorPeersUpdate ./${ORG_NAME}MSPanchors.tx -channelID ${CHANNEL_NAME} -asOrg ${ORG_NAME}MSP
  if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to generate Anchor update configuration transaction...${NC}"
    exit 1
  fi
  if [ "$ARCH" == "Darwin" ]; then
    rm "${CONFIGTX_FILE}t"
  fi
  echo -e "${BROWN} CRYPTO FILES GENERATED FOR ${ORG_NAME}${NC}"
}

function replaceCAkey() {
  COMPOSE_CA_FILE=./docker-compose.yaml
  
  CURRENT_DIR=$PWD
  cd ./crypto-config/peerOrganizations/${ORG_NAME}.example.com/ca/
  PRIV_KEY=$(ls *_sk)
  cd "$CURRENT_DIR"/
  echo $PWD
  sed $OPTS "s/CA_PRIVATE_KEY/${PRIV_KEY}/g" "$COMPOSE_CA_FILE"
 
  if [ "$ARCH" == "Darwin" ]; then
    rm "$COMPOSE_CA_FILE"
  fi
}

function dockerNetworkSetup() {
  echo "##########################################################"
  echo "#############  Starting Docker network   #################"
  echo "##########################################################"
  docker-compose -f docker-compose.yaml up -d 
  sleep 30
  CLI_CNTR=$(docker ps | grep cli| awk '{print $1}')
  if [ ${CLI_CNTR} == "" ]; then
    echo "Error while starting the containers"
    exit 1
  fi
  docker exec ${CLI_CNTR} ./buildNetwork.sh ${ORG_NAME} ${CHANNEL_NAME} ${NUM_PEERS} ${CHAINCODE_NAME} ${CHAINCODE_VERSION} ${CHAINCODE_PATH}
}

startNetwork $1