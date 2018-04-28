#/bin/bash
NONE='\033[00m'
RED='\033[01;31m'
GREEN='\033[01;32m'
YELLOW='\033[01;33m'
PURPLE='\033[01;35m'
CYAN='\033[01;36m'
WHITE='\033[01;37m'
BOLD='\033[1m'
UNDERLINE='\033[4m'

coinGithubLink=https://github.com/ausmcc/kkc
coinPort=7878
coinRpc=7879
coinDaemon=koalakashd
baseCoinCore=.koalakash
coinConfigFile=koalakash.conf
MAX=10

getIp() {
    echo -e "${BOLD}Resolving VPS Ip Address${NONE}"

    #Get ip
    mnip=$(curl --silent ipinfo.io/ip)

    #Attempt 3 more time to get the ip
    ipRegex="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"
    if ! [[ $mnip =~ $ipRegex ]] ; then
        echo
        echo "Could not resolve VPS Ip Address. Retrying"

        maxAttempts=3
        for (( c=1; c <= maxAttempts; c++ ));
        do
            sleep 5

            mnip=$(curl --silent ipinfo.io/ip)

            if [[ $mnip =~ $ipRegex ]] ; then
                break;
            else
                echo -e "${RED}* Attempt ${c} failed.${NONE}";
            fi
        done
    fi

    #Ask manually for ip
    if ! [[ $mnip =~ $ipRegex ]] ; then
        echo
        maxAttempts=3
        for (( c=0; c < maxAttempts; c++ ));
        do
            read -e -p "Input your ip manually (example ip format 123.123.123.123) :" mnip

            if [[ $mnip =~ $ipRegex ]] ; then
                break
            else
                echo -e "${RED}* The IP Address doesn't respect the required format.${NONE}";
            fi
        done
    fi

    #Ask manually for ip
    if ! [[ $mnip =~ $ipRegex ]] ; then
        echo
        echo -e "${RED}Could not resolve VPS Ip Address. Exiting${NONE}"
        exit 0;
    fi

    echo && echo -e "${GREEN}* Done. Your VPS Ip Address is ${mnip}.${NONE}";
}

askForNumberOfMasternodes() {
    existingNumberOfMasternodes=$(($(alias | grep "${coinDaemon}" | wc -l) + 0));

    echo -e "${BOLD}"
    read -e -p "You currently have ${existingNumberOfMasternodes} masternodes installed. How many masternodes do you want to install? (Default value is 1 masternodes) [1] :" numberOfMasternodes
    echo -e "${NONE}"

    re='^[0-9]+$'
    if ! [[ $numberOfMasternodes =~ $re ]] ; then
       numberOfMasternodes=1
    fi

    portArray=()
    rpcArray=()
    daemonArray=()
    coreArray=()

    mnStart=$((existingNumberOfMasternodes + 1))
    mntotal=$((existingNumberOfMasternodes + numberOfMasternodes))
    for (( c=mnStart; c <= mntotal; c++ ));
    do
        tempPort=$((coinPort + (c - 1)))
        tempRpc=$((coinRpc + (c + 100)))
        tempDaemon="$coinDaemon$c"
        tempCore="$baseCoinCore$c"

        portArray+=($tempPort);
        rpcArray+=($tempRpc);
        daemonArray+=($tempDaemon);
        coreArray+=($tempCore);
    done
}

checkForUbuntuVersion() {
   echo "[1/${MAX}] Checking Ubuntu version..."
    if [[ `cat /etc/issue.net`  == *16.04* ]]; then
        echo -e "${GREEN}* You are running `cat /etc/issue.net` . Setup will continue.${NONE}";
    else
        echo -e "${RED}* You are not running Ubuntu 16.04.X. You are running `cat /etc/issue.net` ${NONE}";
        echo && echo "Installation cancelled" && echo;
        exit;
    fi
}

updateAndUpgrade() {
    echo
    echo "[2/${MAX}] Runing update and upgrade. Please wait..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq -y > /dev/null 2>&1
    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq > /dev/null 2>&1
    echo -e "${GREEN}* Done${NONE}";
}

setupSwap() {
    echo -e "${BOLD}"
    read -e -p "Add swap space? (Recommended for VPS that have 1GB of RAM) [Y/n] :" add_swap
    if [[ ("$add_swap" == "y" || "$add_swap" == "Y" || "$add_swap" == "") ]]; then
        swap_size="4G"
    else
        echo -e "${NONE}[3/${MAX}] Swap space not created."
    fi

    if [[ ("$add_swap" == "y" || "$add_swap" == "Y" || "$add_swap" == "") ]]; then
        echo && echo -e "${NONE}[3/${MAX}] Adding swap space...${YELLOW}"
        sudo fallocate -l $swap_size /swapfile
        sleep 2
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        echo -e "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null 2>&1
        sudo sysctl vm.swappiness=10
        sudo sysctl vm.vfs_cache_pressure=50
        echo -e "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf > /dev/null 2>&1
        echo -e "vm.vfs_cache_pressure=50" | sudo tee -a /etc/sysctl.conf > /dev/null 2>&1
        echo -e "${NONE}${GREEN}* Done${NONE}";
    fi
}

installFail2Ban() {
    echo
    echo -e "[4/${MAX}] Installing fail2ban. Please wait..."
    sudo apt-get -y install fail2ban > /dev/null 2>&1
    sudo systemctl enable fail2ban > /dev/null 2>&1
    sudo systemctl start fail2ban > /dev/null 2>&1
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

installFirewall() {
    echo
    echo -e "[5/${MAX}] Installing UFW. Please wait..."
    sudo apt-get -y install ufw > /dev/null 2>&1
    sudo ufw allow OpenSSH > /dev/null 2>&1

    for (( c=0; c < numberOfMasternodes; c++ )) ;
    do
        sudo ufw allow "${portArray[c]}/tcp" > /dev/null 2>&1
    done

    echo "y" | sudo ufw enable > /dev/null 2>&1
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

installDependencies() {
    echo
    echo -e "[6/${MAX}] Installing dependecies. Please wait..."
    sudo apt-get install bc git nano rpl wget python-virtualenv -qq -y > /dev/null 2>&1
    sudo apt-get install build-essential libtool automake autoconf -qq -y > /dev/null 2>&1
    sudo apt-get install autotools-dev autoconf pkg-config libssl-dev -qq -y > /dev/null 2>&1
    sudo apt-get install libgmp3-dev libevent-dev bsdmainutils libboost-all-dev -qq -y > /dev/null 2>&1
    sudo apt-get install software-properties-common python-software-properties -qq -y > /dev/null 2>&1
    sudo add-apt-repository ppa:bitcoin/bitcoin -y > /dev/null 2>&1
    sudo apt-get update -qq -y > /dev/null 2>&1
    sudo apt-get install libdb4.8-dev libdb4.8++-dev -qq -y > /dev/null 2>&1
    sudo apt-get install libminiupnpc-dev -qq -y > /dev/null 2>&1
    sudo apt-get install libzmq5 -qq -y > /dev/null 2>&1
    sudo apt-get install virtualenv -qq -y > /dev/null 2>&1
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

downloadWallet() {
    echo
    echo -e "[7/${MAX}] Compiling wallet. Please wait, this might take a while to complete..."

    cd && mkdir new && cd new

    git clone $coinGithubLink kkc > /dev/null 2>&1
    cd kkc/src > /dev/null 2>&1

    #build level db
    cd leveldb > /dev/null 2>&1
    chmod 755 build_detect_platform > /dev/null 2>&1
    make libleveldb.a libmemenv.a > /dev/null 2>&1
    cd .. > /dev/null 2>&1

    #build secp256k1
    cd secp256k1  > /dev/null 2>&1
    chmod 755 autogen.sh > /dev/null 2>&1
    ./autogen.sh > /dev/null 2>&1
    cd .. > /dev/null 2>&1

    #build wallet
    make -f makefile.unix USE_UPNP=-  > /dev/null 2>&1

    wget $coinDownloadLink > /dev/null 2>&1
    mv $coinDownloadedFile $coinDaemon > /dev/null 2>&1
    chmod 755 $coinDaemon > /dev/null 2>&1

    echo -e "${NONE}${GREEN}* Done${NONE}";
}

installWallet() {
    echo
    echo -e "[8/${MAX}] Installing wallet. Please wait..."
    strip $coinDaemon  > /dev/null 2>&1

    for (( c=0; c < numberOfMasternodes; c++ )) ;
    do
        cp $coinDaemon ${daemonArray[c]} > /dev/null 2>&1
        chmod 755 ${daemonArray[c]} > /dev/null 2>&1
        sudo mv ${daemonArray[c]} /usr/bin  > /dev/null 2>&1
    done

    cd && sudo rm -rf new > /dev/null 2>&1
    cd
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

configureWallet() {
    echo
    echo -e "[9/${MAX}] Configuring wallet. Please wait..."

    rpcuser='eGgwcFbVX0z6eGgwcFbVX0z6'
    rpcpass='f4dsoD6cbqdbf4dsoD6cbqdb'
    masternodePrivateKeyArray=()

    for (( c=0; c < numberOfMasternodes; c++ )) ;
    do
        cd
        mkdir ${coreArray[c]}
        cd ${coreArray[c]}
        touch $coinConfigFile
        chmod 755 $coinConfigFile
        cd

        echo -e "rpcuser=${rpcuser}\nrpcpassword=${rpcpass}\nrpcport=${rpcArray[c]}\nrpcallowedip=127.0.0.1\nlisten=1\nserver=1\ndaemon=1\nport=${portArray[c]}" > ~/${coreArray[c]}/$coinConfigFile

        ${daemonArray[c]} -datadir="$(pwd)/${coreArray[c]}" > /dev/null 2>&1
        sleep 5

        mnkey=$(${daemonArray[c]} -datadir="$(pwd)/${coreArray[c]}" masternode genkey)
        masternodePrivateKeyArray+=($mnkey)

        ${daemonArray[c]} -datadir="$(pwd)/${coreArray[c]}" stop > /dev/null 2>&1

        sleep 5

        echo -e "rpcuser=${rpcuser}\nrpcpassword=${rpcpass}\nrpcport=${rpcArray[c]}\nrpcallowip=127.0.0.1\ndaemon=1\nserver=1\nlisten=1\ntxindex=1\nlistenonion=0\nport=${portArray[c]}\nmasternode=1\nmasternodeaddr=${mnip}:${portArray[c]}\nmasternodeprivkey=${mnkey}\naddnode=ns1.kkc.space\naddnode=ns2.kkc.space\naddnode=ns3.kkc.space\naddnode=ns4.kkc.space\naddnode=ns5.kkc.space\naddnode=ns6.kkc.space\naddnode=ns7.kkc.space\naddnode=ns8.kkc.space\naddnode=ns9.kkc.space\naddnode=ns10.kkc.space" > ~/${coreArray[c]}/$coinConfigFile


    done

    echo -e "${NONE}${GREEN}* Done${NONE}";
}

startWallet() {
    echo
    echo -e "[10/${MAX}] Starting wallet daemon..."

    for (( c=0; c < numberOfMasternodes; c++ )) ;
    do
        ${daemonArray[c]} -datadir="$(pwd)/${coreArray[c]}" > /dev/null 2>&1
        (crontab -l ; echo "@reboot ${daemonArray[c]} -datadir="$(pwd)/${coreArray[c]}" > /dev/null 2>&1")| crontab -

        tempAliasName="${daemonArray[c]}"
        tempAliasCommand="${daemonArray[c]} -datadir=$(pwd)/${coreArray[c]}"

        echo -e "alias $tempAliasName=\"$tempAliasCommand\"" | sudo tee -a ~/.bashrc > /dev/null 2>&1
        sleep 5
    done

    source ~/.bashrc  > /dev/null 2>&1

    echo -e "${GREEN}* Done${NONE}";
}

clear
cd

echo
echo -e "${YELLOW}----------------------------------------------------------------------------------${NONE}"
echo -e "${YELLOW}|                                                                                |${NONE}"
echo -e "${YELLOW}|       @@@@&&&&%                   #%%%%%%%#                   (((((((((        |${NONE}"
echo -e "${YELLOW}|        %@&&&&&&&                  #%%%%%%%#                  ((((((#(/         |${NONE}"
echo -e "${YELLOW}|         .&&&&&&&&                 #%%%%%%%#                 (###((((,          |${NONE}"
echo -e "${YELLOW}|           &&&&&&&&/               #%%%%%%%#               *#####(((            |${NONE}"
echo -e "${YELLOW}|            &&&&&&&&&              #%%%%%%%#              #####((((             |${NONE}"
echo -e "${YELLOW}|             .&&&&&&&&             #%%%%%%%#             ###(((#(               |${NONE}"
echo -e "${YELLOW}|               &&&&&&&&(           #%%%%%%%#           /#((#####                |${NONE}"
echo -e "${YELLOW}|                &&&&&&&%%          #%%%%%%%#          ######(((                 |${NONE}"
echo -e "${YELLOW}|                 /&&&&&%%%         #%%%%%%%#         ########,                  |${NONE}"
echo -e "${YELLOW}|                   &&&%%%%%.       #%%%%%%%#       .########                    |${NONE}"
echo -e "${YELLOW}|                    &%%%%%%%%      #%%%%%%%#      ########(                     |${NONE}"
echo -e "${YELLOW}|                     .%%%%%%%%     #%%%%%%%#     %#######.                      |${NONE}"
echo -e "${YELLOW}|                       %%%%%%%%.   #%%%%%%%#   .%%%%%###                        |${NONE}"
echo -e "${YELLOW}|                        %%%%%%%%(  #%%%%%%%#  (%%%%%###                         |${NONE}"
echo -e "${YELLOW}|                       %%%%%%%%&   #%%%%%%%#   %%%######                        |${NONE}"
echo -e "${YELLOW}|                     #&&%%%%%%%    #%%%%%%%#    #%#######/                      |${NONE}"
echo -e "${YELLOW}|                    &&&%%%%%%      #%%%%%%%#      #######((                     |${NONE}"
echo -e "${YELLOW}|                   &&&%%%%%%       #%%%%%%%#       #########                    |${NONE}"
echo -e "${YELLOW}|                 &&&&%%%%%#        #%%%%%%%#        (######(((                  |${NONE}"
echo -e "${YELLOW}|                &&&&&&%%%          #%%%%%%%#          ###((((((                 |${NONE}"
echo -e "${YELLOW}|              #&&&&&&&%%           #%%%%%%%#           ####(((((/               |${NONE}"
echo -e "${YELLOW}|             &&&&&&&&&             #%%%%%%%#             #((((((((              |${NONE}"
echo -e "${YELLOW}|            &&&&&&&&&              #%%%%%%%#              #((((((##             |${NONE}"
echo -e "${YELLOW}|          #&&&&&&&&/               #%%%%%%%#               ,((((((((/           |${NONE}"
echo -e "${YELLOW}|         &&&&&&&&&                 #%%%%%%%#                 (((((((((          |${NONE}"
echo -e "${YELLOW}|       *&&&&&&&&&                  #%%%%%%%#                  ((((((((/.        |${NONE}"
echo -e "${YELLOW}|      &&&&&&&&&                    #%%%%%%%#                    ((((((((/       |${NONE}"
echo -e "${YELLOW}|     @@@&&&&&&                     #%%%%%%%#                     (((((((//      |${NONE}"
echo -e "${YELLOW}|                                                                                |${NONE}"
echo -e "${YELLOW}|${NONE}               ${BOLD}------ Koala Kash Coin Masternode installer ------${NONE}               ${YELLOW}|${NONE}"
echo -e "${YELLOW}|                                                                                |${NONE} "
echo -e "${YELLOW}----------------------------------------------------------------------------------${NONE} "

echo -e "${BOLD}"
read -p "This script will setup your Koala Kash Masternodes. Do you wish to continue? (y/n)?" response
echo -e "${NONE}"

if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
    getIp
    askForNumberOfMasternodes
    checkForUbuntuVersion
    updateAndUpgrade
    setupSwap
    installFail2Ban
    installFirewall
    installDependencies
    downloadWallet
    installWallet
    configureWallet
    startWallet

    echo && echo -e "${BOLD}The VPS side of your masternode has been installed. Save the masternode ip and private key so you can use them to complete your local wallet part of the setup${NONE}".

    for (( c=0; c < numberOfMasternodes; c++ )) ;
    do
        echo && echo -e "Masternode $((c + 1 + existingNumberOfMasternodes))";
        echo && echo -e "${BOLD}IP:${NONE} ${mnip}:${portArray[c]}";
        echo && echo -e "${BOLD}Private Key:${NONE} ${masternodePrivateKeyArray[c]}";
        echo && echo -e "${BOLD}Daemon:${NONE} ${daemonArray[c]}";
        echo && echo -e "${BOLD}Core Folder:${NONE} ${coreArray[c]}";
        echo
    done

    echo && echo -e "${BOLD}Continue with the cold wallet part of the setup${NONE}" && echo
    exec bash
else
    echo && echo "Installation cancelled" && echo
fi
