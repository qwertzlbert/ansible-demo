#!/bin/bash

DEPENDENCIES="'docker' 'docker-compose' 'ansible' 'jq'"
CONTAINER_COUNT=5
CONF=test.cfg

# change working directory to make relative paths working correctly
cd "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# check dependencies 
for dependency in $DEPENDENCIES
do
	dep=$(whereis $dependency)
	if  [[ ! $dep ]]; then
	echo "needed dependency $dependency missing! Aborting..."
	exit 1
	fi
done

# setup docker containers

# build docker-compose.yml
echo "creating docker-compose.yml"
cat << EOF > test/docker-compose.yml 
version: '3'

services:
EOF

i=0
for instance in $(jq '.[]' $CONF)
do
role=$(jq -rc ".[$i].role" $CONF)
os=$(jq -rc ".[$i].os" $CONF)
number=$(jq -rc ".[$i].number" $CONF)

if [ -d test/$os/ ]; then


cat << EOF >> test/docker-compose.yml 
  $role:
    build:
      context: ./$os
    command: /usr/sbin/sshd -D
    deploy:
      replicas: $number
EOF
fi
i=$i+1
done

cd test/
echo "creating docker image"
sudo docker-compose build
# start scale of docker containers 
echo "starting containers"
# --compatibility flag used instead of --scale (https://github.com/docker/compose/issues/5586)
# to make use of replicas 
sudo docker-compose --compatibility up -d 

cd ..

if [ -e hosts ]; then
	mv hosts hosts.bak
fi

# create hosts file for ansible
touch hosts

allroles=$(jq -r '.[].role' $CONF)
# get names of running containers
containers=$(sudo docker ps --format '{{.Names}}')

echo $containers
echo $allroles

for role in $allroles
do
	echo $role 
	# create hosts file for ansible
cat << EOF >> hosts

[$role]
EOF

# find all container with role
for container in $containers
do
	echo $container
	if [[ $container = *$role* ]]; then
		echo $container
		ip=$(sudo docker exec $container hostname -i)
cat << EOF >> hosts
$container ansible_host=$ip ansible_user=root ansible_ssh_pass=password ansible_connection=paramiko ansible_python_interpreter=/usr/bin/python3
EOF
	fi
done
done

# test playbooks 
ansible-playbook -i hosts deploy.yml

if [ $?=0 ]; then
	echo="playbook worked as expected"
else
	echo="some error has occured"
fi

# cleanup 
#if [ -e hosts.bak ]; then
#	mv hosts.bak hosts
#fi
cd test/
sudo docker-compose down
exit 0
