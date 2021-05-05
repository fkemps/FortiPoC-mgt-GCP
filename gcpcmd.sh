#! /bin/bash

# This script is to perform Google Cloud Platform (GCP) actions for creating, starting, stopping, deleting FortiPoC's
# 2018113001 Ferry Kemps, Initial release
# 2018120401 Ferry Kemps, added --zone argument to override default zone
# 2019011601 Ferry Kemps, added variables, conditional gcloud cmd executions
# 2019020401 Ferry Kemps, added simple menu enable/disable setting
# 2019031301 Ferry Kemps, added config file option
# 2019033001 Ferry Kemps, added gcp repo option to load images and poc-definitions
# 2019033002 Ferry Kemps, added sme as product to facilitate sme-event combos
# 2019050201 Ferry Kemps, increased amount of PoC-definitions to load
# 2019060301 Ferry Kemps, updated FPIMAGE to 1-5-49
# 2019062501 Ferry Kemps, added xa as product to facilitate NSE Xperts Academy events
# 2019070101 Ferry Kemps, increased poc definitions to 6
# 2019081401 Ferry Kemps, added test as product to facilitate temp installs
# 2019081501 Ferry Kemps, changed example config file name to be diff from gcpcmd command
# 2019083001 Ferry Kemps, expanded poc definitions to 8
# 2019100701 Ferry Kemps, added FPPREPEND to custom label instances names.
# 2019101001 Ferry Kemps, added config file check on action build
# 2019101101 Ferry Kemps, added listpubip option to retrieve pub IPs (concatenated for other script)
# 2019101802 Ferry Kemps, added FSW, FSA, appsec as a products/solutions
# 2019102301 Ferry Kemps, Updated the help info
# 2019110101 Ferry Kemps, Commented out simple menu option. Some screen output cleanup
# 2019110441 Ferry Kemps, Adding random sleep time to avoid GCP DB lock error
# 2019110501 Ferry Kemps, Little output corrections
# 2019110601 Ferry Kemps, Moved logfiles to logs directory
# 2019111101 Ferry Kemps, Added automatic defaults per ~/.fpoc/gcpcmd.conf
# 2019111102 Ferry Kemps, Expanded user defaults
# 2019111401 Ferry Kemps, Added add/remove IP-address to GCP ACL
# 2019111501 Ferry Kemps, Added instance clone function
# 2019111502 Ferry Kemps, Changed number generator, added comments
# 2019112201 Ferry Kemps, Fixed license server inquiry
# 2019112202 Ferry Kemps, Added conf dir creation and seq fix
# 2019112501 Ferry Kemps, Clarified GCP billing project ID
# 2019112502 Ferry Kemps, Changed GCP instance labling to list owner
# 2019112503 Ferry Kemps, Changed moment of conf and log dir creation
# 2019112601 Ferry Kemps, Added global list based on owner label
# 2019112801 Ferry Kemps, Empty license server fix
# 2019112901 Ferry Kemps, Cloning now supports labeling
# 2019120501 Ferry Kemps, Added <custom-name> for product/solution, arguments sorted alphabetic
# 2020011001 Ferry Kemps, Added [IP-address] option to --ip-address-add|remove and --ip-address-list
# 2020012701 Ferry Kemps, Use fortipoc-1.7.7 by default, add disclaimer, declare PoC-definitions, introduced group-management
# 2020012703 Ferry Kemps, Corrected CONFFILE check
# 2020012704 Ferry Kemps, Code clean-up, group management
# 2020012705 Ferry Kemps, Added --initials option for group management
# 2020013101 Ferry Kemps, Fixed -d option, added group function for cloning
# 2020022001 Ferry Kemps, Cleared GCPREPO example
# 2020052501 Ferry Kemps, Modified banner
# 2020060201 Ferry Kemps, Added option to change machine-type
# 2020072201 Ferry Kemps, Improved WARNING message on missing software packages.
# 2020081301 Ferry Kemps, Replaced gcloud beta command
# 2020081302 Ferry Kemps, Changed GCP license server input request
# 2020082601 Ferry Kemps, Pre-populated ProjectId and Service Account preferences
# 2020082701 Ferry Kemps, Added -p|--preferences option, renamed -c|--config file to -b|--build-file, improved preference questions.
# 2020110301 Ferry Kemps, Changed standard machine-types to 5 options, added SSH-key option, choice for snapshot on cloning
# 2020110401 Ferry Kemps, Added online new version checking
# 2021040601 Ferry Kemps, Rewrite of cloning from snapshot to machine-image to avoid clone limits
# 2021050401 Ferry Kemps, Added fortipoc-deny-default tag to close default GCP open ports
# 2021050501 Ferry Kemps, Little typo fixes
GCPCMDVERSION="2021050501"

# Disclaimer: This tool comes without warranty of any kind.
#             Use it at your own risk. We assume no liability for the accuracy,, group-management
#             correctness, completeness, or usefulness of any information
#             provided nor for any sort of damages using this tool may cause.

# Zones where to deploy. You can adjust if needed to deploy closest to your location
ASIA="asia-southeast1-b"
EUROPE="europe-west4-a"
#EUROPE="europe-west1-b"
AMERICA="us-central1-c"

# ------------------------------------------------
# ------ No editing needed beyond this point -----
# ------------------------------------------------

# Let's create uniq logfiles with date-time stamp
PARALLELOPT="--joblog logs/logfile-`date +%Y%m%d%H%M%S` -j 100 "
POCDEFINITION1=""
POCDEFINITION2=""
POCDEFINITION3=""
POCDEFINITION4=""
POCDEFINITION5=""
POCDEFINITION6=""
POCDEFINITION7=""
POCDEFINITION8=""

###############################
#   Functions
###############################
function displayheader() {
clear
echo "---------------------------------------------------------------------"
echo "             FortiPoC Toolkit for Google Cloud Platform             "
echo "---------------------------------------------------------------------"
echo ""
}

# Function to display personal config preferences
function displaypreferences() {
  local CONFFILE=$1
  echo "Your personal configuration preferences"
  echo ""
  cat ${CONFFILE}
}

# Function to validate IP-address format
function validateIP() {
  local ip=$1
  local stat=1
  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
     OIFS=$IFS
     IFS='.'
     ip=($ip)
     IFS=$OIFS
     [[ ${ip[0]} -le 239 && ${ip[1]} -le 255 \
     && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
     stat=$?
  fi
  return $stat
}

# Function to add/remove workshop location Public IP-address to GCP ACL to allow access
function gcpaclupdate() {
   CMD=$1
   PUBLICIP=$2
   if [ -z ${PUBLICIP} ]; then
      # Obtain current public IP-address
      PUBLICIP=`dig TXT -4 +short o-o.myaddr.l.google.com @ns1.google.com | sed -e 's/"//g'`
   fi
   validateIP ${PUBLICIP}
   [ ! $? -eq 0 ] && (echo "Public IP not retreavable or not valid"; exit)
   if [ ${CMD} == add ]; then
      echo "Adding public-ip ${PUBLICIP} to GCP ACL to allow access from this location"
      while read line
      do
         if [ -z ${SOURCERANGE} ]; then
            SOURCERANGE="$line"
         else
            SOURCERANGE="${SOURCERANGE},$line"
         fi
      done < <(gcloud compute firewall-rules list --filter="name=workshop-source-networks" --format=json|jq -r '.[] .sourceRanges[]')
      SOURCERANGE="${SOURCERANGE},${PUBLICIP}"
      gcloud compute firewall-rules update workshop-source-networks --source-ranges=${SOURCERANGE}
      echo "Current GCP ACL list"
      gcloud compute firewall-rules list --filter="name=workshop-source-networks" --format=json|jq -r '.[] .sourceRanges[]'
      echo ""
   elif [ ${CMD} == remove ]; then
      echo "Removing public-ip ${PUBLICIP} to GCP ACL to remove access from this location"
      while read line
      do
         if [ -z ${SOURCERANGE} ]; then
            [ ! $line == ${PUBLICIP} ] && SOURCERANGE="$line"
         else
            [ ! $line == ${PUBLICIP} ] && SOURCERANGE="${SOURCERANGE},$line"
         fi
      done < <(gcloud compute firewall-rules list --filter="name=workshop-source-networks" --format=json|jq -r '.[] .sourceRanges[]')
      gcloud compute firewall-rules update workshop-source-networks --source-ranges=${SOURCERANGE}
      echo "Current GCP ACL list"
      gcloud compute firewall-rules list --filter="name=workshop-source-networks" --format=json|jq -r '.[] .sourceRanges[]'
      echo ""
    else
      echo "Listing public-ip addresses on GCP ACL"
      gcloud compute firewall-rules list --filter="name=workshop-source-networks" --format=json|jq -r '.[] .sourceRanges[]'
      echo ""
   fi
}

# Function to list all global instances
function gcplistglobal {
  OWNER=$1
  FPGROUP=$2
  if [ -z ${FPGROUP} ]; then
    gcloud compute instances list --filter="labels.owner:${OWNER}"
  else
    gcloud compute instances list --filter="(labels.owner:${OWNER} OR labels.group:${FPGROUP})"
  fi
}

# Function to build a FortiPoC instance on GCP
function gcpbuild {

  if [ "${CONFIGFILE}" == "" ]; then
     echo "Build file missing. Use -b option to specify or to generate fpoc-example.conf file"
     exit
  fi

  RANDOMSLEEP=$[($RANDOM % 10) + 1]s
  FPPREPEND=$1
  ZONE=$2
  PRODUCT=$3
  FPTITLE=$4
  INSTANCE=$5
  INSTANCENAME="fpoc-${FPPREPEND}-${PRODUCT}-${INSTANCE}"

  echo "==> Sleeping ${RANDOMSLEEP} seconds to avoid GCP DB locking"
  sleep ${RANDOMSLEEP}
  echo "==> Creating instance ${INSTANCENAME}"
  gcloud compute \
  instances create ${INSTANCENAME} \
  --project=${GCPPROJECT} \
  --service-account=${GCPSERVICEACCOUNT} \
  --verbosity=info \
  --zone=${ZONE} \
  --machine-type=${MACHINETYPE} \
  --subnet=default --network-tier=PREMIUM \
  --maintenance-policy=MIGRATE \
  --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
  --min-cpu-platform=Intel\ Broadwell\
  --tags=fortipoc-http-https-redir,fortipoc-deny-default,workshop-source-networks \
  --image=${FPIMAGE} \
  --image-project=${GCPPROJECT} \
  --boot-disk-size=200GB \
  --boot-disk-type=pd-standard \
  --boot-disk-device-name=${INSTANCENAME} \
  --labels=${LABELS}

  # Give Google 60 seconds to start the instance
  echo ""; echo "==> Sleeping 90 seconds to allow FortiPoC booting up"; sleep 90
  INSTANCEIP=`gcloud compute instances describe ${INSTANCENAME} --zone=${ZONE} | grep natIP | awk '{ print $2 }'`
  echo ${INSTANCENAME} "=" ${INSTANCEIP}
  curl -k -q --retry 1 --connect-timeout 10 https://${INSTANCEIP}/ && echo "FortiPoC ${INSTANCENAME} on ${INSTANCEIP} reachable"
  [ $? != 0 ] && echo "==> Something went wrong. The new instance is not reachable"

  # Now configure, load, prefetch and start PoC-definition
  [ "${FPTRAILKEY}" != "" ] && (echo "==> Registering FortiPoC"; gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command "reg trial ${FPTRAILKEY}")
  [ "${FPTITLE}" != "" ] && (echo "==> Setting title"; gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command "set gui title \"${FPTITLE}\"")
  gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command 'set guest passwd guest'
  [ "${GCPREPO}" != "" ] && (echo "==> Adding repository"; gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command "repo add gcp-${GCPREPO} https://gcp.repository.fortipoc.com/~#{GCPREPO}/ --unsigned")
  [ ! -z ${LICENSESERVER} ] && (echo "==> Setting licenseserver"; gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command "set license https://${LICENSESERVER}/")
  [ ! -z ${POCDEFINITION1} ] && (echo "==> Loading poc-definition 1"; gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command "poc repo define \"${POCDEFINITION1}\" refresh")
  [ ! -z ${POCDEFINITION2} ] && (echo "==> Loading poc-definition 2"; gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command "poc repo define \"${POCDEFINITION2}\" refresh")
  [ ! -z ${POCDEFINITION3} ] && (echo "==> Loading poc-definition 3"; gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command "poc repo define \"${POCDEFINITION3}\" refresh")
  [ ! -z ${POCDEFINITION4} ] && (echo "==> Loading poc-definition 4"; gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command "poc repo define \"${POCDEFINITION4}\" refresh")
  [ ! -z ${POCDEFINITION5} ] && (echo "==> Loading poc-definition 5"; gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command "poc repo define \"${POCDEFINITION5}\" refresh")
  [ ! -z ${POCDEFINITION6} ] && (echo "==> Loading poc-definition 6"; gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command "poc repo define \"${POCDEFINITION6}\" refresh")
  [ ! -z ${POCDEFINITION7} ] && (echo "==> Loading poc-definition 7"; gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command "poc repo define \"${POCDEFINITION7}\" refresh")
  [ ! -z ${POCDEFINITION8} ] && (echo "==> Loading poc-definition 8"; gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command "poc repo define \"${POCDEFINITION8}\" refresh")
  echo "==> Prefetching all images and documentation"; gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command 'poc prefetch all'
  [ "${POCLAUNCH}" != "" ] && (echo "==> Launching poc-definition"; gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command "poc launch \"${POCLAUNCH}\"")
  [ "${SSHKEYPERSONAL}" != "" ] && (echo "==> Adding personal SSH key"; gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command "set ssh authorized keys \"${SSHKEYPERSONAL}\"")
#  [ "${FPSIMPLEMENU}" != "" ] && (echo "==> Setting GUI-mode to simple"; gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command "set gui simple ${FPSIMPLEMENU}")
  echo "==> End of Build phase <=="; echo ""
}

# Function to clone a FortiPoC instance on GCP
function gcpclone {
  RANDOMSLEEP=$[($RANDOM % 10) + 1]s
  FPPREPEND=$1
  ZONE=$2
  PRODUCT=$3
  FPNUMBERTOCLONE=$4
  INSTANCE=$5
  CLONESOURCE="fpoc-${FPPREPEND}-${PRODUCT}-${FPNUMBERTOCLONE}"
  CLONEMACHINEIMAGE="fpoc-${FPPREPEND}-${PRODUCT}"
  INSTANCENAME="fpoc-${FPPREPEND}-${PRODUCT}-${INSTANCE}"

  echo "==> Sleeping ${RANDOMSLEEP} seconds to avoid GCP DB locking"
  sleep ${RANDOMSLEEP}
  echo "==> Create instance ${INSTANCENAME}"
#  gcloud compute instances create ${INSTANCENAME} \
#  --project=${GCPPROJECT} \
#  --service-account=${GCPSERVICEACCOUNT} \
#  --verbosity=info \
#  --zone=${ZONE} \
#  --machine-type=n1-standard-4 \
#  --subnet=default --network-tier=PREMIUM \
#  --maintenance-policy=MIGRATE \
#  --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
#  --min-cpu-platform=Intel\ Broadwell \
#  --tags=fortipoc-http-https-redir,workshop-source-networks \
#  --disk "name=${INSTANCENAME},device-name=${INSTANCENAME},mode=rw,boot=yes,auto-delete=yes" \
#  --labels=${LABELS}
   gcloud beta compute instances create ${INSTANCENAME} \
   --project=${GCPPROJECT} \
   --zone=${ZONE} \
   --source-machine-image ${CLONEMACHINEIMAGE}
}

# Function to start FortiPoC instance
function gcpstart {
  FPPREPEND=$1
  ZONE=$2
  PRODUCT=$3
  INSTANCE=$4
  INSTANCENAME="fpoc-${FPPREPEND}-${PRODUCT}-${INSTANCE}"
  echo "==> Starting instance ${INSTANCENAME}"
  gcloud compute instances start ${INSTANCENAME} --zone=${ZONE}
}

# Function to stop FortiPoC instance
function gcpstop {
  FPPREPEND=$1
  ZONE=$2
  PRODUCT=$3
  INSTANCE=$4
  INSTANCENAME="fpoc-${FPPREPEND}-${PRODUCT}-${INSTANCE}"
  echo "==> Stopping instance ${INSTANCENAME}"
#  gcloud compute ssh admin@${INSTANCENAME} --zone ${ZONE} --command 'poc eject' # not working if admin pwd is set
  gcloud compute instances stop ${INSTANCENAME} --zone=${ZONE}
}

# Function to delete FortiPoC instance
function gcpdelete {
  FPPREPEND=$1
  ZONE=$2
  PRODUCT=$3
  INSTANCE=$4
  INSTANCENAME="fpoc-${FPPREPEND}-${PRODUCT}-${INSTANCE}"
  echo "==> Deleting instance ${INSTANCENAME}"
  echo yes | gcloud compute instances delete ${INSTANCENAME} --zone=${ZONE}
}

# Function to delete FortiPoC instance
function gcpmachinetype {
  FPPREPEND=$1
  ZONE=$2
  PRODUCT=$3
  MACHINETYPE=$4
  INSTANCE=$5
  INSTANCENAME="fpoc-${FPPREPEND}-${PRODUCT}-${INSTANCE}"
  echo "==> Changing machine-type of ${INSTANCENAME}"
  gcloud compute instances set-machine-type ${INSTANCENAME} --machine-type=${MACHINETYPE} --zone=${ZONE}
}

# Function to display the help
function displayhelp {
  echo ' _____          _   _ ____              _____           _ _    _ _      __               ____  ____ ____'
  echo '|  ___|__  _ __| |_(_)  _ \ ___   ___  |_   _|__   ___ | | | _(_) |_   / _| ___  _ __   / ___|/ ___|  _ \'
  echo '| |_ / _ \|  __| __| | |_) / _ \ / __|   | |/ _ \ / _ \| | |/ / | __| | |_ / _ \|  __| | |  _| |   | |_) |'
  echo '|  _| (_) | |  | |_| |  __/ (_) | (__    | | (_) | (_) | |   <| | |_  |  _| (_) | |    | |_| | |___|  __/'
  echo '|_|  \___/|_|   \__|_|_|   \___/ \___|   |_|\___/ \___/|_|_|\_\_|\__| |_|  \___/|_|     \____|\____|_|'
  echo ""
  echo "(Version: ${GCPCMDVERSION})"
  echo "Default deployment region: ${ZONE}"
  echo "Personal instance identification: ${FPPREPEND}"
  echo "Default product: ${PRODUCT}"
  echo ""
  echo "Usage: $0 [OPTIONS] [ARGUMENTS]"
  echo "       $0 [OPTIONS] <region> <product> <action>"
  echo "       $0 [-b configfile] <region> <product> build"
  echo "       $0 [OPTIONS] [region] [product] list"
  echo "       $0 [OPTIONS] [region] [product] listpubip"
  echo "OPTIONS:"
  echo "        -b    --build-file                     File for building instances. Leave blank to generate example"
  echo "        -d    --delete-config                  Delete default user config settings"
  echo "        -g    --group                          Group name for shared instances"
  echo "        -i    --initials                       Specify intials on instance name for group management"
  echo "        -ia   --ip-address-add [IP-address]    Add current public IP-address to GCP ACL"
  echo "        -ir   --ip-address-remove [IP-address] Remove current public IP-address from GCP ACL"
  echo "        -il   --ip-address-list                List current public IP-address on GCP ACL"
  echo "        -p    --preferences                    Show personal config preferences"
  echo "        -lg   --list-global                    List all your instances globally"
  echo "ARGUMENTS:"
  echo "       region  : america, asia, europe"
  echo "       product : appsec, fad, fpx, fsa, fsw, fwb, sme, test, xa or <custom-name>"
  echo "       action  : build, clone, delete, list, machinetype, listpubip, start, stop"
  echo "                 action build needs -b configfile. Use ./gcpcmd.sh -b to generate fpoc-example.conf"
  echo ""
  [ "${NEWVERSION}" = "true" ] && echo "*** Newer version ${ONLINEVERSION} is available online on GitHub ***"; echo ""
}

###############################
#   start of program
###############################
# Check if required software is available and exit if missing
type gcloud > /dev/null 2>&1 || (echo ""; echo "WARNING: gcloud SDK not installed"; exit 1)
[ $? -eq 1 ] && exit
type parallel > /dev/null 2>&1 || (echo ""; echo "WARNING: parallel software not installed"; exit 1)
[ $? -eq 1 ] && exit
type jq > /dev/null 2>&1 || (echo""; echo "WARNING: jq software not installed"; exit 1)
[ $? -eq 1 ] && exit
echo ""

# Check on first run and user specific defaults
# Chech if .fpoc logs and conf directories exists, create if it doesn't exist to store peronal perferences
[ ! -d ~/.fpoc/ ] && mkdir ~/.fpoc
[ ! -d logs ] && mkdir logs
[ ! -d conf ] && mkdir conf

# Check online if there is a newer Version
ONLINEVERSION=`curl --fail --silent --retry-max-time 2 http://www.4xion.com/gcpcmdversion.txt`
[ ! -z "${ONLINEVERSION}" ] && [ ${ONLINEVERSION} -gt ${GCPCMDVERSION} ] && NEWVERSION="true"

eval GCPCMDCONF="~/.fpoc/gcpcmd.conf"
if [ ! -f ${GCPCMDCONF} ]; then
   echo "Welcome to FortiPoc Toolkit for Google Cloud Platform"
   echo "This is your first time use of gcpcmd.sh and no preferences are set. Let's set them!"
   read -p "Provide your initials e.g. fl : " CONFINITIALS
   read -p "Provide your name to lable instanced e.g. flastname : " CONFGCPLABEL
   read -p "Provide a groupname for shared instances (optional) : " CONFGCPGROUP
   until [ ! -z ${CONFREGION} ]; do
      read -p "Provide your region 1) Asia, 2) Europe, 3) America : " CONFREGIONANSWER
      case ${CONFREGIONANSWER} in
         1) CONFREGION="${ASIA}";;
         2) CONFREGION="${EUROPE}";;
         3) CONFREGION="${AMERICA}";;
      esac
   done

# Request ProjectId from GCP and use that if no projectId is entered
   GCPPROJECTID=`gcloud projects list --format json | jq -r '.[] .projectId'`
   read -p "Provide your GCP billing project ID [${GCPPROJECTID}] : " CONFPROJECTNAME
   [ -z ${CONFPROJECTNAME} ] &&  CONFPROJECTNAME=${GCPPROJECTID}

# Request default Compute Service Account and use that if no Service Account is entered
   GCPSRVACCOUNT=`gcloud iam service-accounts list --filter=Compute --format=json| jq -r '.[] .email'`
   read -p "Provide your GCP service account [${GCPSRVACCOUNT}] : " CONFSERVICEACCOUNT
   [ -z ${CONFSERVICEACCOUNT} ] && CONFSERVICEACCOUNT=${GCPSRVACCOUNT}

   until [[ ${VALIDIP} -eq 1 ]]; do
      read -p "IP-address of FortiPoC license server (if available) : " CONFLICENSESERVER
      if [ -z ${CONFLICENSESERVER} ];then
         VALIDIP=1
      else
         validateIP ${CONFLICENSESERVER}
         VALIDIP=!$?
      fi
   done

# Obtain pesonal SSH-key for FortiPoC access
   SSHKEYPERSONAL="_no_key_found"
   if [ -f ~/.ssh/id_rsa.pub ]; then
     SSHKEYPERSONAL=`head -1 ~/.ssh/id_rsa.pub`
   fi
     read -p "Provide your SSH public key for FortiPoC access (optional) [${SSHKEYPERSONAL}] : " CONFSSHKEYPERSONAL
     CONFSSHKEYPERSONAL="${SSHKEYPERSONAL}"

   cat << EOF > ${GCPCMDCONF}
GCPPROJECT="${CONFPROJECTNAME}"
GCPSERVICEACCOUNT="${CONFSERVICEACCOUNT}"
LICENSESERVER="${CONFLICENSESERVER}"
FPPREPEND="${CONFINITIALS}"
ZONE="${CONFREGION}"
LABELS="fortipoc=,owner=${CONFGCPLABEL}"
FPGROUP="${CONFGCPGROUP}"
PRODUCT="test"
SSHKEYPERSONAL="${CONFSSHKEYPERSONAL}"
EOF
   echo ""
fi
source ${GCPCMDCONF}

# Verify if label "owner" is populated in prefences file. If not than gcpcmd.sh was updated.
OWNER=`echo ${LABELS} | grep owner | cut -d "=" -f 3`
if [ -z ${OWNER} ]  && [ ! "$1" == "-d" ]; then
   echo "Run ./gcpcmd.sh -d because your configured preferences are from older gcpcmd.sh version."
   [ -f ${GCPCMDCONF} ] && displaypreferences ${GCPCMDCONF}
   exit
fi

# Verify if SSHKEY was populated from prefences file. If not than gcpcmd.sh was updated.
if [ -z "${SSHKEYPERSONAL}" ]  && [ ! "$1" == "-d" ]; then
   echo "Run ./gcpcmd.sh -d because your configured preferences are from older gcpcmd.sh version."
   [ -f ${GCPCMDCONF} ] && displaypreferences ${GCPCMDCONF}
   exit
fi

# Verify if group variable preference is set, else gcpcmd.sh was update
if [ -z ${FPGROUP} ] && [ ! `grep FPGROUP ${GCPCMDCONF}` ] && [ ! "$1" == "-d" ]; then
   echo "Run ./gcpcmd.sh -d because your configured preferences are from older gcpcmd.sh version."
   [ -f ${GCPCMDCONF} ] && displaypreferences ${GCPCMDCONF}
   exit
elif [ -z ${FPGROUP} ]; then
     FPGROUP=${OWNER}
fi

# Verify if Service Account preference is set, else append to personal preference file
if [ ! `grep GCPSERVICEACCOUNT ${GCPCMDCONF}` ]; then
   GCPSRVACCOUNT=`gcloud iam service-accounts list --filter=Compute --format=json| jq -r '.[] .email'`
   echo "Adding default Service Account to your personal preference file"
   echo "GCPSERVICEACCOUNT=\"${GCPSRVACCOUNT}\"" >> ${GCPCMDCONF}
fi

# Handling options given
while [[ "$1" =~ ^-.* ]]; do
case $1 in
  -b | --build-file)
#   Check if a build config file is provided
    CONFIGFILE=$2
    RUN_CONFIGFILE="true"
    shift
    ;;
  -d | --delete-defaults) echo "Delete default user settings"
     rm ${GCPCMDCONF}
     exit
     ;;
  -g | --group)
     FPGROUP=$2
     SET_FPGROUP="true"
     OVERRIDE_FPGROUP=${FPGROUP}
     shift
     ;;
  -i | --initials)
     FPPREPEND=$2
     SET_FPPREPEND="true"
     OVERRIDE_FPPREPEND=${FPPREPEND}
     shift
     ;;
  -ia | --ip-address-add)
     gcpaclupdate add $2
     exit
     ;;
  -ir | --ip-address-remove)
     gcpaclupdate remove $2
     exit
     ;;
  -il | --ip-address-list)
     gcpaclupdate list
     exit
     ;;
  -p | --preferences)
     displayheader
     displaypreferences ${GCPCMDCONF}
     exit
     ;;
  -lg | --list-global)
     RUN_LISTGLOBAL=true
     ;;
  -*)
   # Report invalid option
     echo "[ERROR] Invalid option ${1}"
     echo ""
     ;;
esac
shift
done

if [ "${RUN_CONFIGFILE}" == "true" ]; then
  if [ ! -z ${CONFIGFILE} ] && [ -e ${CONFIGFILE} ]; then
    source ${CONFIGFILE}
    if [ ! -z ${SET_FPGROUP} ] && [ ${SET_FPGROUP} == "true" ];then
      FPGROUP=${OVERRIDE_FPGROUP}
    fi
  else
    echo "Config file not found. Example file written as fpoc-example.conf"
    cat << EOF > fpoc-example.conf
# Uncomment and speficy to override user defaults
#GCPPROJECT="${GCPPROJECT}"
#GCPSERVICEACCOUNT="${GCPSERVICEACCOUNT}"
#FPPREPEND="${FPPREPEND}"
#LABELS="${LABELS}"
#LICENSESERVER="${LICENSESERVER}"

# --- edits below this line ---
# Specify FortiPoC instance details.
MACHINETYPE="n1-standard-4"
FPIMAGE="fortipoc-1-7-14-clear"
#FPSIMPLEMENU="enable"
FPTRAILKEY='ES-xamadrid-201907:765eb11f6523382c10513b66a8a4daf5'
#GCPREPO=""
#FPGROUP="${FPGROUP}"
POCDEFINITION1="poc/ferry/FortiWeb-Basic-solution-workshop-v2.2.fpoc"
#POCDEFINITION2="poc/ferry/FortiWeb-Advanced-Solutions-Workshop-v2.5.fpoc"
#POCDEFINITION3=""
#POCDEFINITION4=""
#POCDEFINITION5=""
#POCDEFINITION6=""
#POCDEFINITION7=""
#POCDEFINITION8=""
#POCLAUNCH="FortiWeb Basic solutions"
EOF
  exit
  fi
fi

if [ "${SET_FPPREPEND}" == "true" ]; then
  FPPREPEND=${OVERRIDE_FPPREPEND}
fi

if [ "${RUN_LISTGLOBAL}" == "true" ]; then
  displayheader
  echo "Listing all global instances for owner:${OWNER} or group:${FPGROUP}"
  echo ""
  gcplistglobal ${OWNER} ${FPGROUP}
  exit
fi

if [ $# -lt 1 ]; then
  displayhelp
  exit
fi

# Populate given arguments
LABELS="fortipoc=,owner=${OWNER},group=${FPGROUP}"
ARGUMENT1=$1
ARGUMENT2=$2
ARGUMENT3=$3

# Validate given arguments
case ${ARGUMENT1} in
  america) ZONE=${AMERICA};;
  asia) ZONE=${ASIA};;
  europe) ZONE=${EUROPE};;
  list) echo "Using your default settings"; ARGUMENT2=${PRODUCT}; ARGUMENT3="list";;
  listpubip) echo "Using your default settings"; ARGUMENT2=${PRODUCT}; ARGUMENT3="listpubip";;
  *) echo "[ERROR: REGION] Specify: america, asia or europe"; echo ""; exit;;
esac

case ${ARGUMENT2} in
  fpx) PRODUCT="fpx"; FPTITLE="FortiProxy\ Workshop";;
  fwb) PRODUCT="fwb"; FPTITLE="FortiWeb\ Workshop";;
  fad) PRODUCT="fad"; FPTITLE="FortiADC\ Workshop";;
  fsa) PRODUCT="fsa"; FPTITLE="FortiSandbox\ Workshop";;
  fsw) PRODUCT="fsw"; FPTITLE="FortiSwitch\ Workshop";;
  sme) PRODUCT="sme"; FPTITLE="SME-event\ Workshop";;
  xa)  PRODUCT="xa"; FPTITLE="Xperts\ Academy\ Workshop";;
  appsec)  PRODUCT="appsec"; FPTITLE="Application\ Security\ Workshop";;
  test)  PRODUCT="test"; FPTITLE="Test\ Instance";;
  list) echo "Using your default settings"; ARGUMENT3="list";;
  listpubip) echo "Using your default settings"; ARGUMENT3="listpubip";;
  *) PRODUCT="${ARGUMENT2}";  FPTITLE="${PRODUCT}\ Workshop";;
esac

case ${ARGUMENT3} in
  build) ACTION="build";;
  clone) ACTION="clone";;
  start) ACTION="start";;
  stop) ACTION="stop";;
  delete) ACTION="delete";;
  machinetype) ACTION="machinetype";;
  list) ACTION="list";;
  listpubip) ACTION="listpubip";;
  *) echo "[ERROR: ACTION] Specify: build, clone, delete, machinetype, list, listpubip, start or stop"; exit;;
esac

displayheader
if  [[ ${ACTION} == build  ||  ${ACTION} == start || ${ACTION} == stop || ${ACTION} == delete || ${ACTION} == machinetype ]]
then
  read -p " Enter amount of FortiPoC's : " FPCOUNT
  read -p " Enter start of numbered range : " FPNUMSTART
  if [ ${ACTION} == "machinetype" ]; then
    read -p " select machine-type : 1) n1-standard-1, 2) n1-standard-2, 3) n1-standard-4, 4) n1-standard-8, 5) n1-standard-16 : " NEWMACHINETYPE
    case ${NEWMACHINETYPE} in
      1) MACHINETYPE="n1-standard-1";;
      2) MACHINETYPE="n1-standard-2";;
      3) MACHINETYPE="n1-standard-4";;
      4) MACHINETYPE="n1-standard-8";;
      5) MACHINETYPE="n1-standard-16";;
      *) echo "Wrong machine type given"; echo ""; exit;;
    esac
  fi
  let --FPCOUNT
  let FPNUMEND=FPNUMSTART+FPCOUNT
  FPNUMSTART=$(printf "%03d" ${FPNUMSTART})
  FPNUMEND=$(printf "%03d" ${FPNUMEND})

  echo ""
  read -p "Okay to ${ACTION} fpoc-${FPPREPEND}-${PRODUCT}-${FPNUMSTART} till fpoc-${FPPREPEND}-${PRODUCT}-${FPNUMEND} in region ${ZONE}.   y/n? " choice
  [ "${choice}" != "y" ] && exit
fi

if  [[ ${ACTION} == clone ]]
then
  displayheader
  read -p " FortiPoC instance number to clone : " FPNUMBERTOCLONE
  read -p " Enter amount of FortiPoC's clones : " FPCOUNT
  read -p " Enter start of numbered range : " FPNUMSTART
  let --FPCOUNT
  let FPNUMEND=FPNUMSTART+FPCOUNT
  FPNUMSTART=$(printf "%03d" ${FPNUMSTART})
  FPNUMEND=$(printf "%03d" ${FPNUMEND})
  FPNUMBERTOCLONE=$(printf "%03d" ${FPNUMBERTOCLONE})
  CLONESOURCE="fpoc-${FPPREPEND}-${PRODUCT}-${FPNUMBERTOCLONE}"
  CLONEMACHINEIMAGE="fpoc-${FPPREPEND}-${PRODUCT}"
  if [ ! -z ${SET_FPGROUP} ] && [ ${SET_FPGROUP} == "true" ];then
    FPGROUP=${OVERRIDE_FPGROUP}
  fi
  echo ""
  read -p "Okay to ${ACTION} ${CLONESOURCE} to fpoc-${FPPREPEND}-${PRODUCT}-${FPNUMSTART} till fpoc-${FPPREPEND}-${PRODUCT}-${FPNUMEND} in region ${ZONE}.   y/n? " choice
  [ "${choice}" != "y" ] && exit
  # Safest is to use fresh machine-image because it includes latest changes and there is not check if a machine-image exists
  # To speed up cloning you could skip machine-image creation and assume there's an machine-image available.
  read -p "Do you want to create a fresh machine-image? (No means the latest machine-image will be used, if available) y/n: " choice
  if [ ${choice} == "y" ]; then
    # Delete any existing machine-image before creating new.There's no overwrite AFAIK and will allow fresh snapshot
    echo "==> Preparing machine-image....be patienced, enjoy a quick espresso"
    echo "y" |  gcloud beta compute machine-images delete ${CLONEMACHINEIMAGE} > /dev/null 2>&1
    gcloud beta compute machine-images create ${CLONEMACHINEIMAGE} \
    --source-instance ${CLONESOURCE} \
    --source-instance-zone=${ZONE} > /dev/null 2>&1
  fi
fi

  echo "==> Lets go...using Owner=${OWNER} or Group=${FPGROUP}, Zone=${ZONE}, Product=${PRODUCT}, Action=${ACTION}"; echo

export -f gcpbuild gcpstart gcpstop gcpdelete gcpclone gcpmachinetype
export CONFIGFILE GCPPROJECT FPIMAGE MACHINETYPE LABELS FPTRAILKEY FPPREPEND POCDEFINITION1 POCDEFINITION2 POCDEFINITION3 POCDEFINITION4 POCDEFINITION5 POCDEFINITION6 POCDEFINITION7 POCDEFINITION8 LICENSESERVER POCLAUNCH NEWMACHINETYPE GCPSERVICEACCOUNT SSHKEYPERSONAL

case ${ACTION} in
  build)  parallel ${PARALLELOPT} gcpbuild  ${FPPREPEND} ${ZONE} ${PRODUCT} "${FPTITLE}" ::: `seq -f%03g ${FPNUMSTART} ${FPNUMEND}`;;
  clone)  parallel ${PARALLELOPT} gcpclone  ${FPPREPEND} ${ZONE} ${PRODUCT} "${FPNUMBERTOCLONE}" ::: `seq -f%03g  ${FPNUMSTART} ${FPNUMEND}`;;
  start)  parallel ${PARALLELOPT} gcpstart  ${FPPREPEND} ${ZONE} ${PRODUCT} ::: `seq -f%03g  ${FPNUMSTART} ${FPNUMEND}`;;
  stop)   parallel ${PARALLELOPT} gcpstop   ${FPPREPEND} ${ZONE} ${PRODUCT} ::: `seq -f%03g  ${FPNUMSTART} ${FPNUMEND}`;;
  delete) parallel ${PARALLELOPT} gcpdelete ${FPPREPEND} ${ZONE} ${PRODUCT} ::: `seq -f%03g  ${FPNUMSTART} ${FPNUMEND}`;;
  machinetype) parallel ${PARALLELOPT} gcpmachinetype ${FPPREPEND} ${ZONE} ${PRODUCT} ${MACHINETYPE} ::: `seq -f%03g  ${FPNUMSTART} ${FPNUMEND}`;;
  list) gcloud compute instances list --filter="(labels.owner:${OWNER} OR labels.group:${FPGROUP}) AND zone~${ZONE}" | grep -e "NAME" -e ${PRODUCT};;
# list) gcloud compute instances list --filter="name~fpoc-${FPPREPEND}-${PRODUCT}"| grep -e "NAME" -e "${ZONE}";;
  listpubip) gcloud compute instances list --filter="(labels.owner:${OWNER} OR labels.group:${FPGROUP}) AND zone~${ZONE}"  | grep -e ${PRODUCT}  | awk '{ printf $5 " " }';;
# listpubip) gcloud compute instances list --filter="name~fpoc-${FPPREPEND}-${PRODUCT}"| grep -e "${ZONE}" | awk '{ printf $5 " " }';;
esac
