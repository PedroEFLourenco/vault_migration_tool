#!/bin/bash

echo $'\n'
echo $'-------------------------------------------- VAULT MIGRATION TOOL -----------------------------------------------\n'
echo $' This tool was created to export and import KEY-VALUE secrets from and to vault.\n'
echo ' Once exported, your secrets WILL BE VULNERABLE. Import them as quickly as possible or delete the exported file.'
echo ' Secrets will get exported to a "secrets.txt" file in the same folder as the script.'
echo
echo $' REQUIREMENTS:'
echo ' - Vault CLI installed. '
echo $' - Token with read permission to export secrets OR write permission to import secrets.\n'
echo
echo ' NOTES:'
echo ' - Please ignore messages like "No value found at secrets/some/path/inside/vault"'
echo '   as this is the CLI response when there are no sub-directories in that path.'
echo $'------------------------------------------------------------------------------------------------------------------\n'
secretsFile=./secrets.txt

exitOnFailure() {
    if [ $? -ne 0 ]; then 
        exit
    fi
}

doOrLeave() {
    $1

    if [ $? -ne 0 ]; then 
        >&2 echo ' Retrying... '
         $1
         exitOnFailure
    fi
}

retryOnFailure() {
    $1

    if [ $? -ne 0 ]; then 
        >&2 echo "Let's try that again..."
         $1
    fi
}


recursiveSecretFetch() {
    #storage of first argument
    local rootDir="$1"
    #shift to ignore first argument
    shift
    #storage of all other arguments as an array
    local arrayOfSubDirs=("$@")

    for element in "${arrayOfSubDirs[@]}"
    do
        echo "Running on $rootDir$element"
        local subdirs="$(retryOnFailure "vault list -tls-skip-verify $rootDir$element/")"
        #check if subdirs has a value or not
        if [ -z "$subdirs" ]; then 
        #replace all whitespaces for = on the result of the vault read, in which we are only keeping the 7th word forward.
            secret=$(tr -s ' ' '=' <<< "$(echo $(retryOnFailure "vault read -tls-skip-verify $rootDir$element/") | cut -d' ' -f 7-)")
            echo $rootDir$element $secret  >> $secretsFile
        else
        #conversion of subdirs string into an array of subdirs
            IFS=' ' read -r -a subDirsArray <<< $(echo $subdirs | cut -d' ' -f 3-)
            recursiveSecretFetch "$rootDir$element" "${subDirsArray[@]}"
        fi
    done
}

printAll() {
    local array=("$@")

    for element in "${array[@]}"
    do
        echo "$element"
    done
}

echo ' What is the Vault address?..............................................................................'
read address

echo ' What is the Vault Token?................................................................................'
read token

doOrLeave "vault login -tls-skip-verify $token"
#MENU
echo "...........What do you want to do?..........."
echo "  1) Export Secrets"
echo "  2) Import Secrets"
echo
read n
case $n in
1) #LOGIC FOR SECRET EXPORT
echo 
echo ' What is the root directory to work on ?.................................................................'
read rootDir
echo 

#reads the list of directories in vault under rootDir
subdirs=$(doOrLeave "vault list -tls-skip-verify $rootDir/") 
#splits the string containing the list, into an array called subDirsArray. Starting from the third word in order to ignore the "Keys ---- " header.
IFS=' ' read -r -a subDirsArray <<< $(echo $subdirs | cut -d' ' -f 3-)

echo ' These are the directories which secrets will get exported:'
printAll "${subDirsArray[@]}"
echo
rm -f secrets.txt
recursiveSecretFetch "$rootDir/" "${subDirsArray[@]}";;

2) #LOGIC FOR SECRETS IMPORT 
#If the file exists, read each line and convert it into a vault write command. Else, just echo that the file is not present.
if test -f "$secretsFile"; then
    while IFS= read -r line
    do
         eval "retryOnFailure 'vault write -tls-skip-verify $line'"
    done < "$secretsFile"
else
    echo "secrets file does not exist in current directory."
fi;;
  *) echo "invalid option";;
esac
