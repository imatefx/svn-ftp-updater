#!/bin/bash 

REPOSITORY=$1
SVN_USER=''
SVN_PASSWD=''
WORKING_DIRECTORY=$2
MOUNT_DIR=''
#REVISION_FROM=` expr ${SVN_REVISION} - 1 `
REVISION_FROM=''
REVISION_TO='HEAD'
FTP_HOST=$3
FTP_USER=$4
FTP_PASSWD=$5
FTP_ROOT_DIR=$6
FILE_LIST=''
REN_DIRECTORY_CMD=''
REN_FILE_CMD=''
GOT_UPDATED_FILES=0
SVN_STATUS=''


#Temporary Initilization
REPOSITORY=''
WORKING_DIRECTORY=''

function MessageLogger
{
	if [[ $2 ]]; then
		echo $(date +%d-%m-%Y_%T) ": $2 : ${FUNCNAME[1]} : $1"
	else
		echo $(date +%d-%m-%Y_%T) ": ${FUNCNAME[1]} : $1"
	fi
}
function DoesDirectoryExists
{
	if [[ -d $1 ]]; then
		MessageLogger "Found directory $1"
		return 0
	else
		MessageLogger "Directory $1 does not exists" "ERROR"
		return 1
	fi
}
function ReadRevision
{
	if REVISION_FROM=$(lftp -e "cat $FTP_ROOT_DIR/.revision ; bye ;" -u$FTP_USER,$FTP_PASSWD $FTP_HOST | awk '{print $1;}' | head -n 1 ;) ;  then
		MessageLogger "Revision From : $REVISION_FROM"
	fi
	if [[ ! $REVISION_FROM ]]; then
		REVISION_FROM='0'
	fi
}
function WriteRevision
{
	MessageLogger "SVN Information"
	svn info  --non-interactive --username=$SVN_USER --password=$SVN_PASSWD   $REPOSITORY
	echo `svn info  --non-interactive --username=$SVN_USER --password=$SVN_PASSWD   $REPOSITORY | grep ^Revision | sed 's/Revision: *//'` > $WORKING_DIRECTORY/.revision
	MessageLogger "Transfering Revision Information"
	lftp -e "mput -O $FTP_ROOT_DIR $WORKING_DIRECTORY/.revision ; bye ; " -u$FTP_USER,$FTP_PASSWD $FTP_HOST ;
	MessageLogger "Transfered Revision Information"
	
}
function GetUpdatedFiles
{
	MessageLogger "Revision From : $REVISION_FROM"

	if [ $REVISION_FROM ]; then
	svn diff --non-interactive --username=$SVN_USER --password=$SVN_PASSWD  --summarize -r$REVISION_FROM:$REVISION_TO $REPOSITORY
	for line in `svn diff --non-interactive --username=$SVN_USER --password=$SVN_PASSWD  --summarize -r$REVISION_FROM:$REVISION_TO $REPOSITORY | grep "^[AM]"`
	do
		if [ $line != "A" ] && [ $line != "AM" ] && [ $line != "M" ]; then
			filename=`echo "$line" |sed "s|$REPOSITORY||g"`
			if [ ! -d $WORKING_DIRECTORY$filename ]; then
				directory=`dirname $filename`
				mkdir -p $WORKING_DIRECTORY$directory
				svn export --non-interactive --username=$SVN_USER --password=$SVN_PASSWD  $line $WORKING_DIRECTORY$filename
				GOT_UPDATED_FILES=1
			fi
		fi
	done
	fi
}
function PutFilesToServer
{
	MessageLogger "Starting Upload to Server"
	if  [ $GOT_UPDATED_FILES -ne "0" ] ; then
		lftp -e "set ftp:list-options -a ; mirror -R --verbose=3 --parallel=10 --no-perms -x ^\.svn/$ --only-newer $WORKING_DIRECTORY/ $FTP_ROOT_DIR; bye ; " -u$FTP_USER,$FTP_PASSWD $FTP_HOST ;
	else
		MessageLogger "No files to Upload to Server"	
	fi
	MessageLogger "Finished Upload to Server"
}
function CleanWorkingDirectory
{
	MessageLogger "Cleaning Working Directory"
	rm -vrf $WORKING_DIRECTORY/*
	MessageLogger "Cleaned Working Directory"
}
function FindDeletedFiles
{
	for line in `svn diff --username=$SVN_USER --password=$SVN_PASSWD --non-interactive --summarize -r$REVISION_FROM:$REVISION_TO $REPOSITORY | grep "^[D]"`
	do
		if [ $line != "D" ]; then
			filename=`echo "$line" |sed "s|$REPOSITORY|$FTP_ROOT_DIR|g"`
			repofilename=`echo "$line"`
			if svn cat --username=$SVN_USER --password=$SVN_PASSWD --non-interactive $repofilename@$REVISION_FROM  &> /dev/null ; then
				if lftp -e "find $filename ; bye ;" -u$FTP_USER,$FTP_PASSWD $FTP_HOST  ;  ERR=$? ;  then
					if [ $ERR -ne 0 ]; then
						MessageLogger "Possible Missing File $filename" "Error"
					else
						REN_FILE_CMD="mv $filename $filename.back.$(date +%d%m%Y-%T) ; $REN_FILE_CMD"
					fi
				fi
			else
				if lftp  -e "cd $filename ; bye ;" -u$FTP_USER,$FTP_PASSWD $FTP_HOST  ;  ERR=$? ; then
					if [ $ERR -ne "0" ]; then
						MessageLogger "Possible Missing Directory $filename" "Error"
					else				
						REN_DIRECTORY_CMD="mv $filename $filename.back.$(date +%d%m%Y-%T) ; $REN_DIRECTORY_CMD ;"
					fi
				fi
			fi
		fi
	done
}
function RenameDeletedFiles
{
	if [[ $REN_FILE_CMD ]]; then
		if lftp -e "$REN_FILE_CMD ; bye ;" -u$FTP_USER,$FTP_PASSWD $FTP_HOST  ;  ERR=$? ;  then
			if [ $ERR -ne "0" ]; then
				MessageLogger "$REN_FILE_CMD" "Error"
			fi
		fi
	else
		MessageLogger "No files to delete"
	fi
	if [[ $REN_DIRECTORY_CMD ]]; then
		if lftp  -e "$REN_DIRECTORY_CMD ; bye ;" -u$FTP_USER,$FTP_PASSWD $FTP_HOST   ; ERR=$? ; then
			if [ $ERR -ne "0" ]; then
				MessageLogger "$REN_DIRECTORY_CMD" "Error"
			fi
		fi
	else
		MessageLogger "No directories to delete"
	fi
}
echo "Working till now"
if  DoesDirectoryExists $WORKING_DIRECTORY ; then
	#CleanWorkingDirectory
	ReadRevision
	FindDeletedFiles
	GetUpdatedFiles
	RenameDeletedFiles
	#PutFilesToServer
	WriteRevision
fi
