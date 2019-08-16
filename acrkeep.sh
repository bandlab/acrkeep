#!/usr/bin/env bash

#
#   Copyright 2019 BandLab Technologies
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

print_help() {
    cat << EOF
Copyright 2019 BandLab Technologies
Bash script to keep space in the Azure Container Registry (ACR)

Usage: ./acrkeep.sh --name=<registry name> --repository=<repository>
    [--time=<time condition>] [--top=<top condition>] [--size=<size condition>]
    [--force] [--dry-run] [--verbosity|-v]
    [--help|-h]

Options:

    --name=<registry name>      Azure registry name
    --repository=<repository>   Repository name

    --time=<time condition>     Keeps latest images by time, seconds. Here's allowed to use short formats:
                                    H - hour(s)
                                    D - day(s)
                                    W - week(s)
                                Example:    '--time=3W' means ACR keeps images which were updated in last three weeks.
                                            Older images will be removed

    --top=<top condition>       Keeps top latest images
                                Example:    '--top=3' means ACR keeps three images which were updated last time. Older
                                            images will be removed

    --size=<size condition>     Keeps images to have total repository size less than condition. Here's allowed to use
                                short formats:
                                    K - kilobyte(s)
                                    M - megabyte(s)
                                    G - gigabyte(s)
                                Example:    '--size=250M' means ACR keeps images with total size less than 250 megabytes

    --dry-run       Just display images which are going to be removed using current options
    --force         Dont't ask to remove each image
    --verbosity, -v Display debug information
    --help, -h      Display usage

Report bugs to:
https://github.com/bandlab/acrkeep/issues

EOF
}

dehumanize_bytes() {
    local res=$(echo $1 | awk '/[0-9]$/{ print $1; next };/[gG]$/{ print $1*1024*1024*1024; next };/[mM]$/{ print $1*1024*1024; next };/[kK]$/{ print $1*1024; next }')
    echo $res
}

dehumanize_seconds() {
    local res=$(echo $1 | awk '/[0-9]$/{ print $1; next };/[wW]$/{ print $1*60*60*24*7; next };/[dD]$/{ print $1*60*60*24; next };/[hH]$/{ print $1*60*60; next }')
    echo $res
}

main() {
    local arg_value
    local by_time
    local by_top
    local by_size
    local deletion_digests
    local deletion_images
    local is_dry
    local is_verbosity
    local force
    local registry
    local repository
    local time_threshold

    local i
    for i in $ARGS
    do
        case $i in
            --dry-run)
                is_dry=true
            ;;
            --force)
                force=" --yes"
            ;;
            --help|-h)
                print_help
                exit
            ;;
            --name=*)
                registry="${i#*=}"
            ;;
            --repository=*)
                repository="${i#*=}"
            ;;
            --time=*[0-9wWdDhH])
                arg_value="${i#*=}"
                by_time=$(dehumanize_seconds $arg_value)
                time_threshold=$(date -v-${by_time}S +%s)
                echo "Task: to keep images by time: elder than $(date -j -f '%s' $time_threshold +'%D %T')"
            ;;
            --top=*)
                arg_value="${i#*=}"
                by_top="${i#*=}"
                echo "Task: to keep top$arg_value images"
            ;;
            --size=*[0-9gGmMkK])
                arg_value="${i#*=}"
                by_size=$(dehumanize_bytes $arg_value)
                echo "Task: to keep latest images with total size less than $arg_value ($by_size bytes)"
            ;;
            --verbosity|-v)
                is_verbosity=true
            ;;
        esac
    done

    local images=$(az acr repository show-manifests --name $registry --repository $repository --output tsv --detail --orderby time_desc --query '[].{Tag: tags[0], Size: imageSize, Updated: lastUpdateTime, Digest: digest}')
    local top=0
    local size=0

    while read -r image; do
        local image_digest=$(echo $image | awk '{ print $4; }')
        local image_size=$(echo $image | awk '{ print $2; }')
        local image_tag=$(echo $image | awk '{ print $1; }')
        local image_updated=$(echo $image | awk '{ print $3; }' | xargs -I '{}' date -j -f "%Y-%m-%dT%H:%M:%S." '{}' +%s 2>/dev/null)
        local reason


        # Check that image was updated earlier than threshold
        if [[ ! -z $by_time ]]; then
            if [[ $image_updated -lt $time_threshold ]]; then
                reason="time"
            fi
        fi

        # Check top position for image
        if [[ ! -z $by_top ]]; then
            top=$((top+1))
            if [[ $top -gt $by_top ]]; then
                reason="top"
            fi
        fi

        # Check that total size of repository is less than condition
        if [[ ! -z $by_size ]]; then
            size=$((size+image_size))
            if [[ $size -gt $by_size ]]; then
                reason="size"
            fi
        fi


        if [[ ! -z $reason ]]; then
            deletion_digests="$deletion_digests $image_digest"

            if [[ "$image_tag" = "None" ]]; then
                deletion_images="$deletion_images orphaned($image_digest)"
            else
                deletion_images="$deletion_images $image_tag"
            fi
        fi

        if [[ "$is_verbosity" = true ]]; then
            echo "digest: $image_digest"
            echo "    size: $image_size"
            echo "    tag: $image_tag"
            echo "    updated: $image_updated"

            case $reason in
                "time")
                    echo "    decision: delete because updated time $image_updated less than $time_threshold"
                ;;
                "top")
                    echo " >> decision: delete because top position $top more than $by_top"
                ;;
                "size")
                    echo " >> decision: delete because summary size $size more than $by_size"
                ;;
                *)
                    echo " >> decision: keep"
                ;;
            esac
        fi
    done <<< "$images"

    if [[ ! -z $deletion_images ]]; then
        echo "Going to delete images:"
        local image
        for image in $deletion_images; do
            echo "    $image"
        done
    else
        echo "Nothing to clear"
    fi

    if [[ "$is_dry" != true ]]; then
        local digest
        for digest in $deletion_digests
        do
            az acr repository delete --name $registry --image $repository@$digest $force
            local result=$?
            if [[ $result -eq 0 ]]; then
                echo "Deleted: $digest"
            fi
        done
    else
        echo "Action skipped in dry run mode"
    fi
}

readonly ARGS="$@"
main
