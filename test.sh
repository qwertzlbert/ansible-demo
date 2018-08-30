#!/bin/bash


DEPENDENCIES="'docker' 'docker-compose' 'ansible' 'sshpass'"

CONTAINER_COUNT=5

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
cd test/
# build docker image
echo "creating docker image"
sudo docker-compose build
# start scale of docker containers 
echo "starting containers"
sudo docker-compose up -d --scale demo=$CONTAINER_COUNT

# get ip addresses
ip_addresses=()
for (( container=1; container<=$CONTAINER_COUNT; container++))
do 
	# receive ip address from container. hostname -i is not really reliable 
	# but works for debian and ubuntu
	ip=$(sudo docker exec test_demo_$container hostname -i)
	ip_addresses+=("$ip")
done
echo ${ip_addresses[*]}

cd ..
if [ -e hosts ]; then
	mv hosts hosts.bak
fi

# create hosts file for ansible
cat << EOF > hosts

[web]
EOF

# use paramiko because of ssh failure with sshpass 
# use python3 because /usr/bin/python is not available 
for ip in "${ip_addresses[@]}"
do
cat << EOF >> hosts
test_$ip ansible_host=$ip ansible_user=root ansible_ssh_pass=password ansible_connection=paramiko ansible_python_interpreter=/usr/bin/python3
EOF
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
#cd test/
#sudo docker-compose down
exit 0
