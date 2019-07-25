#!/bin/bash


function removefiles() {
    rm -rf *.block *.tx *.yaml *.txt crypto crypto-config
}
function removeNetwork() {
    docker stop $(docker ps -aq)
    docker rm $(docker ps -aq)
    docker rmi $(docker images | grep dev | awk '{print $3}') 2>&1
    echo "y" | docker network prune
    echo "y" | docker volume prune
    removefiles
}