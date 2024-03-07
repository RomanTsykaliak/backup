#!/bin/bash
#
# Copyright (C) 2018, 2021, 2023 Roman Tsyklaiak
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
########################################################################
#
# Make a backup of user files to an archive drive
#
# Loads all drives and mounts the file system of all archive drives.
# It checks whether there are multiple drives with the right UUID.  If
# thre are none, the program aborts.  If there is more than one drive
# with the same UUID, it checks for the most recent back up made in
# each drive and makes a back up there.  Directory structure is set by
# the user through variables following this description.  If some of
# the directories are missing, the program aborts.  All the output
# about the operation goes into the temporary file, contents of which
# is repeated to the standard output.  Upon the end of the operation,
# the user is prompted to: unmount the file systems of all archive
# drives and remove the temporary file; or, only unmount drives and copy
# the temporary file into the user's current directory; or, do nothing
# and end the execution.
# Destination archive drive should contain a file named "last" with the
# of the result of `echo $(date +%F)`, e.g., "2024-03-07".  That date,
# e.g., "2024-03-07", should be the name of the first folder, which will
# be linked to all folders, in turn, in subsequent backups.
#
# Usage:
#   backup.bash
#
# Available OPTIONS: NONE
#
# Invoke like below (only as root):
#   ./backup.bash
#
# Return: 2 if an error occurs
########################################################################
# Specify UUID of an archive drive
UUID_ARCHIVE='0e342ac9-4124-487f-a375-30a551b6f35f'
# Specify source directory to get files from
SOURCE_DIR='/home/danika/'
# Specify files and directories to archive with a time stamp
SOURCE_TIME_STAMP=("Documents Copyrighted" "Library Copyrighted" "System Copyrighted" "Sales Copyrighted" ".bash_history" ".emacs")
# Specify files and directories to archive incrementally
SOURCE_INCREMENTAL=("Pictures" "Videos" "Audiobooks" "Music" "Perverted")
# Specify the mounting options for an archive drive
MOUNT_OPTS='-t ext4 -o rw,relatime,user_xattr,acl,barrier,nodelalloc,journal_checksum,journal_async_commit,data=journal,commit=1'
########################################################################
# DO NOT MODIFY STARTING FROM HERE!!
scsi_host_scan()
{
    # Specify the hosts to scan for an archive drive
    local host_scan_list=( /sys/class/scsi_host/*/scan )
    for host_scan in ${host_scan_list[@]}
    do
        # enable a potential archive drive
        echo "- - -" > $host_scan || {
            echo "$0: ${FUNCNAME[0]}: cound not start the"\
                 "drive at \"$host_scan\"" 1>&2; return 1; }
    done
    return 0
}
find_archive()
{
    if ! [[ $# -eq 1 ]]
    then
        echo "$0: ${FUNCNAME[0]}: usage: ${FUNCNAME[0]}"\
             "<array-to-pass-drive-names-to>" 1>&2
        return 1
    fi
    # test blkid, activate host[0..4], return sda1
    if [[ -b "$(blkid --uuid $UUID_ARCHIVE 2>&1)" ]]
    then
        SOURCE=( $(blkid --output device --match-token\
                         UUID=$UUID_ARCHIVE 2>&1) )
        printf "\n%s: %s: %s\n" "$0" "${FUNCNAME[0]}"\
               "found archive at \"${SOURCE[*]}\" SUCCESSFULLY"
        return 0
    else
        echo "$0: ${FUNCNAME[0]}: failed to find an archive drive"\
             "with UUID \"$UUID_ARCHIVE\"" 1>&2;
        return 1;
    fi
}
mount_archive()
{
    [[ $# -eq 2 ]] || { echo "$0: ${FUNCNAME[0]}: use: ${FUNCNAME[0]}"\
                             "<drive-names> <mount-points>" 1>&2;
                        return 1; }
    for src in ${SOURCE[@]}
    do
        local mount_point=$(findmnt -n -o TARGET -S $src)
        if [[ -n "$mount_point" ]]
        then
            local mount_rw=$(findmnt -n -o OPTIONS -S $src | grep "rw,")
            if [[ -n $mount_rw ]]
            then
                DESTINATION[$src]=$mount_point
                printf "\n%s: %s: %s %s\n" "$0" "${FUNCNAME[0]}"\
                       "\"$src\" already mounted on"\
                       "\"${DESTINATION[$src]}\" SUCCESSFULLY"
            else
                mount -o remount,rw $src "$mount_point" &&
                    eval DESTINATION[$src]='$mount_point' &&
                    printf "\n%s: %s: %s %s %s\n" "$0" "${FUNCNAME[0]}"\
                           "remounted as writable \"$src\" on"\
                           "\"${DESTINATION[$src]}\" SUCCESSFULLY" || {
                        echo "$0: ${FUNCNAME[0]}: failed to remount"\
                            "\"$src\" on \"${DESTINATION[$src]}\"" 1>&2;
                        return 1; }
            fi
        else
            DESTINATION[$src]=$(mktemp -d -p /tmp tmp.XXXXXXXXXX) &&
                mount $MOUNT_OPTS $src "${DESTINATION[$src]}" &&
                printf "\n%s: %s: %s %s\n" "$0" "${FUNCNAME[0]}"\
                       "archive \"$src\" mounted on"\
                       "\"${DESTINATION[$src]}\" SUCCESSFULLY" || {
                    echo "$0: ${FUNCNAME[0]}: failed to mount \"$src\""\
                         "on \"${DESTINATION[$src]}\"" 1>&2;
                    [[ -d "${DESTINATION[$src]}" ]] &&
                        rm -rf "${DESTINATION[$src]}";
                    return 1; }
        fi
    done
    return 0;
}
check_if_dir() {
    if [[ $# -eq 2 ]] && [[ -d "$1" ]] &&
           eval local perm=$2 && [[ ${#perm} -eq 1 ]]; then
        #echo "$0: ${FUNCNAME[0]}: number of args: \"$#\"" 1>&2
        #echo "$0: ${FUNCNAME[0]}: input argumets: \"$@\"" 1>&2
        [[ -d $1 ]] && eval local permissions=$(stat -Lc "%A" "$1") &&
            [[ ( ${permissions:0:4} =~ $2 ) ]] && return 0 || {
                echo "$0: ${FUNCNAME[0]}: NOT \"${perm}\" directory:"\
                     "\"$1\"" 1>&2; return 1; }
    else
        echo "$0: ${FUNCNAME[0]}: usage: ${FUNCNAME[0]} <directory>"\
             "<permission>" 1>&2
        return 1
    fi
}
function select_archive()
{
    [[ $# -eq 2 ]] || { echo "$0: ${FUNCNAME[0]}: usage:"\
           "${FUNCNAME[0]} <mount-points> <directory>" 1>&2; return 1; }
    local -A stamps_disks # ( [2021-07-08]=/dev/sdd1 ... )
    for disk in ${!DESTINATION[@]}
    do
        local -a stamp
        [[ -r "${DESTINATION[$disk]}/last" ]] &&
            readarray -t stamp < "${DESTINATION[$disk]}/last" || {
              echo "$0: ${FUNCNAME[0]}: \"${DESTINATION[$disk]}/last\""\
                   "not readable: no previous stamp" 1>&2; return 1; }
        check_if_dir "${DESTINATION[$disk]}/${stamp[0]}" "r" || {
            echo "$0: ${FUNCNAME[0]}: linked directory"\
                 "\"${DESTINATION[$disk]}/${stamp[0]}\""\
                 "not readable" 1>&2; return 1; }
        stamps_disks[${stamp[0]}]=$disk
    done
    # sorted time stamps: "${keys[0]}" shall refer to the newest one
    local -a keys=(
     $( for key in ${!stamps_disks[@]}; do echo $key; done | sort -r ) )
    # mount point to make the back up into
    DIRECTORY=${DESTINATION[${stamps_disks[${keys[0]}]}]}
    return 0
}
do_backup()
{
    if [[ $# -eq 2 ]] && [[ -d $1 ]] && [[ -f $2 ]]
    then
        local destination=$1 output=$2
    else
        echo "$0: ${FUNCNAME[0]}: usage: ${FUNCNAME[0]}"\
             "<destination-directory> <output-file>" 1>&2
        return 1
    fi
    check_if_dir "$SOURCE_DIR" "r" || {
        echo "$0: ${FUNCNAME[0]}: source directory \"$SOURCE_DIR\""\
             "not readable" 1>&2
        return 1
    }
    check_if_dir "$destination" "w" || {
        echo "$0: ${FUNCNAME[0]}: destination directory"\
             "\"$destination\" not writable" 1>&2
        return 1
    }
    local -a stamp
    [[ -r "${destination}/last" ]] &&
        readarray -t stamp < "${destination}/last" || {
            echo "$0: ${FUNCNAME[0]}: \"${destination}/last\""\
                 "not readable: no previous stamp" 1>&2; return 1; }
    local new="$(date +%F)"
    check_if_dir "${destination}/${stamp[0]}" "r" || {
        echo "$0: ${FUNCNAME[0]}: linked directory"\
             "\"${destination}/${stamp[0]}\" not readable" 1>&2
        return 1
    }
    # check if directory already exists, echo to last.temp
    ! [[ -d "${destination}/${new}" ]] || {
        echo "$0: ${FUNCNAME[0]}: destination directory"\
             "\"${destination}/${new}\" already exists" 1>&2
        return 1
    }
    trap 'exec 3>&-; rm -f $error' RETURN # clean up on return
    local error=$(mktemp) || {
        echo "$0: ${FUNCNAME[0]}: no file for the error output" 1>&2
        return 1
    }
    exec 3<> $error
    local count
    for (( count=0; count < ${#SOURCE_TIME_STAMP[@]}; count++ ))
    do
        local temp_stamp="${SOURCE_DIR}/${SOURCE_TIME_STAMP[$count]}"
        SOURCE_TIME_STAMP[$count]=$temp_stamp
    done
    # rsync --checksum --numeric-ids
    rsync --archive --delete\
          --link-dest="${destination}/${stamp[0]}" --compress\
          --stats --itemize-changes\
          "${SOURCE_TIME_STAMP[@]}"\
          "${destination}/${new}" 2>&3 | tee -a $output
    if ! [[ -s "$error" ]]
    then
        echo $new > "${destination}/last"
        printf "\n%s: %s: %s\n\n" "$0" "${FUNCNAME[0]}"\
               "backup with a time stamp completed SUCCESSFULLY"
    else
        echo "$0: ${FUNCNAME[0]}: backup with a time stamp for"\
             "\"${destination}/${new}\" failed" 1>&2
        printf "%s\n\n" "$(<$error)"
        return 1
    fi
    for (( count=0; count < ${#SOURCE_INCREMENTAL[@]}; count++ ))
    do
        local temp_incr="${SOURCE_DIR}/${SOURCE_INCREMENTAL[$count]}"
        SOURCE_INCREMENTAL[$count]=$temp_incr
    done
    # rsync --numeric-ids
    rsync --archive --stats --itemize-changes\
          "${SOURCE_INCREMENTAL[@]}"\
          "${destination}/" 2>&3 | tee -a $output
    if ! [[ -s "$error" ]]
    then
        printf "\n%s: %s: %s\n\n" "$0" "${FUNCNAME[0]}"\
               "incremental backup completed SUCCESSFULLY"
    else
        echo "$0: ${FUNCNAME[0]}: incremental backup for"\
             "\"${destination}/\" failed" 1>&2
        printf "%s\n\n" "$(<$error)"
        return 1
    fi
    return 0
}
cleanup()
{
    # global clean up
    unset -v UUID_ARCHIVE SOURCE_DIR SOURCE_TIME_STAMP
    unset -v SOURCE_INCREMENTAL MOUNT_OPTS
    unset -v SOURCE DESTINATION DIRECTORY OPTIONS
    PS3=$OPS3; unset -v OPS3
}
########################################################################
# DO NOT MODIFY STARTING FROM HERE!!
# scsi_host_scan || {
#     echo "$0: failed to start all usb drives" 1>&2; cleanup; exit 2; }
declare -ag SOURCE # the array of archive drives
find_archive SOURCE || {
    echo "$0: failed to find the archive drive" 1>&2; cleanup; exit 2; }
# mount archives' file systems
declare -Ag DESTINATION # the array of disks and mount points
mount_archive SOURCE DESTINATION || {
    echo "$0: failed to mount archive drives" 1>&2; cleanup; exit 2; }
declare -g DIRECTORY # to make a back up into
select_archive DESTINATION DIRECTORY || {
    echo "$0: couldn't select an archive drive" 1>&2; cleanup; exit 2; }
trap 'rm -f $OUTPUT; unset OUTPUT' EXIT # to ensure deletion
OUTPUT=$(mktemp)  || {
    echo "$0: no file to duplicate output into" 1>&2; cleanup; exit 2; }
printf "\n%s: %s %s\n\n" "$0" "back up into \"$DIRECTORY\""\
                       "and output into \"${OUTPUT}\""
do_backup "$DIRECTORY" $OUTPUT || {
    echo "$0: could not do a backup" 1>&2; cleanup; exit 2; }
# get user input, process
OPTIONS=( "unmount all archive drives, remove output"\
          "keep all archive drives mounted, keep output" )
OPS3=$PS3 # keep it as it was
PS3="Pick an option: "
select opt in "${OPTIONS[@]}" "quit"
do
    case "$REPLY" in
        1 ) for disk in ${SOURCE[@]}; do
                umount $disk && printf "\n%s: %s\n\n" "$0"\
                           "drive \"$disk\" unmounted SUCCESSFULLY" || {
                        echo "$0: failed to unmount \"$SOURCE\"" 1>&2
                        cleanup; exit 2; }
                [[ -z ${DESTINATION[$disk]#/tmp/tmp.??????????} ]] &&
                    [[ -d ${DESTINATION[$disk]} ]] &&
                    [[ -z $(ls -A ${DESTINATION[$disk]} 2>&1) ]] &&
                    rm -rf ${DESTINATION[$disk]} || {
                        echo "$0: ${FUNCNAME[0]}: not a directory: did"\
                          "not remove \"${DESTINATION[$disk]}\"" 1>&2; }
            done
            break;;
        2 ) cp ${OUTPUT} "${PWD}" && printf "\n%s: %s\n\n" "$0"\
               "output \"$OUTPUT\" copied to \"$PWD\" SUCCESSFULLY" || {
                      echo "$0: failed to copy output \"$OUTPUT\" to"\
                           "\"$PWD\"" 1>&2; cleanup; exit 2; }
            break;;
        $(( ${#OPTIONS[@]}+1 )) ) # the last option: quit
            break;;
        * ) echo "$0: You've picked an invalid option $REPLY" 1>&2
            continue;;
    esac
done
cleanup; exit 0
########################################################################
