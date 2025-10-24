#!/usr/bin/env bash

# get_services() {
#     output_file="services.txt"
#     > "$output_file"
#
#     find . -type f -name "docker-compose.yml" | while read -r file; do
#       echo "$file" >> "$output_file"
#       yq eval '.services | keys' "$file" | grep -v '^#' | sed 's/^..//' | grep -v '^$' >> "$output_file"
#     done
#
#     echo "Service names have been written to $output_file"
# }


# Function to read the file and build the map
build_compose_map() {
    local compose_file=""
    while IFS= read -r line; do
        line=$(echo "$line" | xargs)

        # Check if the line starts with "./" (indicating a compose file)
        if [[ $line == ./* ]]; then
            line="${line:2}"
            complete_list+=("$line")
            compose_file=("$SCRIPT_DIR$line")
            compose_list+=("$compose_file")
            echo $compose_file

        else
            complete_list+=("$line")
            service_list+=("$line")
            service_to_compose["$line"]="$compose_file"
        fi
    done < "$services_file"

    # NOTE: This loads in custom groups
    if [[ -f "$config_file" ]]; then

        local group_names=()
        while IFS= read -r line; do
            group_names+=("$line")
        done <<< "$(yq e '.groups | keys | .[]' "$config_file")"

        for group_name in $group_names; do
            local services=$(yq e ".groups.\"$group_name\"[]" "$config_file")

            local service_list_csv=""
            while IFS= read -r service; do
                if [[ -z "$service_list_csv" ]]; then
                    service_list_csv="$service"
                else
                    service_list_csv+=", $service"
                fi
            done <<< "$services"

            # echo "group:$group_name = $service_list_csv"

            custom_groups["group:$group_name"]="$service_list_csv"
            complete_list+=("group:$group_name")
            echo "Loaded group: group:$group_name"
        done
    else
        echo "Warning: Configuration file not found at $config_file"
    fi

}

dstart() {
    local build_list=()
    local start_list=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b)
                shift
                while [[ $# -gt 0 && $1 != -* ]]; do
                    #TODO: Find out why -v wasn't working in the if

                    # Check to see if the input is a group
                    local check="${custom_groups["$1"]}"
                    if [[ ${#check} -gt 1 ]]; then
                        local add_services=$(_csv_to_array "${custom_groups["$1"]}")
                        for services in $add_services; do
                            build_list+=("$services")
                        done
                    else
                        build_list+=("$1")
                    fi
                    shift
                done

                docker compose -f ${SCRIPT_DIR}network/docker-compose.yml up -d god_debug

                # If they do `-d` with no options it will do it to all of them here and break
                if [[ ${#build_list[@]} -eq 0 ]]; then
                    for arg in $compose_list; do
                        docker compose -f $arg build --no-cache
                        docker compose -f $arg up -d
                    done
                    break
                fi

                # Turn on specified services
                for arg in $build_list; do

                    # This is if the input is a compose file or a service
                    if [[ ${compose_list[@]} =~ $arg ]] then
                        docker compose -f $arg build --no-cache
                        docker compose -f $arg up -d
                    else
                        docker compose -f ${service_to_compose["$arg"]} build $arg --no-cache
                        docker compose -f ${service_to_compose["$arg"]} up -d $arg
                    fi
                done
                ;;
            -u)
                shift
                while [[ $# -gt 0 && $1 != -* ]]; do
                    # Check to see if the input is a group
                    local check="${custom_groups["$1"]}"
                    if [[ ${#check} -gt 1 ]]; then
                        local add_services=$(_csv_to_array "${custom_groups["$1"]}")
                        for services in $add_services; do
                            start_list+=("$services")
                        done
                    else
                        start_list+=("$1")
                    fi
                    shift
                done

                docker compose -f ${SCRIPT_DIR}network/docker-compose.yml up -d god_debug

                # No specific service so all of them
                if [[ ${#start_list[@]} -eq 0 ]]; then
                    for arg in $compose_list; do
                        docker compose -f $arg up -d
                    done
                    break
                fi  

                # Loading specific service
                for arg in $start_list; do
                    if [[ ${compose_list[@]} =~ $arg ]] then
                        docker compose -f $arg up -d
                    else
                        docker compose -f ${service_to_compose["$arg"]} up -d $arg
                    fi
                done
                ;;
            -h)
                shift
                echo "Usage: dstart [OPTIONS] [SERVICES...]"
                echo ""
                echo "Options:"
                echo "  -b    Build specified services or all services if none are provided."
                echo "        Usage: dstart -b [service1] [service2] ..."
                echo "        If no services are specified, builds all services listed in the compose files."
                echo ""
                echo "  -u    Start specified services or all services if none are provided."
                echo "        Usage: dstart -u [service1] [service2] ..."
                echo "        If no services are specified, starts all services listed in the compose files."
                echo ""
                echo "  -h    Display this help message."
                echo ""
                echo "Examples:"
                echo "  dstart -b <service1> <service2>    Build and start the specified services."
                echo "  dstart -u <service1> <service2>    Start the specified services without rebuilding."
                echo "  dstart -h                          Display this help message."
                ;;

            *)
                echo "This is the * case $1"
                shift
                break
                ;;

        esac
    done
}

dstop() {
    local stop_list=()
    local down_list=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s)
                shift
                while [[ $# -gt 0 && $1 != -* ]]; do
                    # Check to see if the input is a group
                    local check="${custom_groups["$1"]}"
                    if [[ ${#check} -gt 1 ]]; then
                        local add_services=$(_csv_to_array "${custom_groups["$1"]}")
                        for services in $add_services; do
                            stop_list+=("$services")
                        done
                    else
                        stop_list+=("$1")
                    fi
                    shift
                done

                if [[ ${#stop_list[@]} -eq 0 ]]; then
                    for arg in $compose_list; do
                        docker compose -f $arg stop
                    done
                    break
                fi  
                for arg in $stop_list; do
                    if [[ ${compose_list[@]} =~ $arg ]] then
                        docker compose -f $arg stop
                    else
                        docker compose -f ${service_to_compose["$arg"]} stop $arg
                    fi
                done
                ;;

            -d)
                shift
                while [[ $# -gt 0 && $1 != -* ]]; do
                    # Check to see if the input is a group
                    local check="${custom_groups["$1"]}"
                    if [[ ${#check} -gt 1 ]]; then
                        local add_services=$(_csv_to_array "${custom_groups["$1"]}")
                        for services in $add_services; do
                        down_list+=("$services")
                        done
                    else
                        down_list+=("$1")
                    fi
                    shift
                done
                if [[ ${#down_list[@]} -eq 0 ]]; then
                    for arg in $compose_list; do
                        docker compose -f $arg down
                    done
                    break
                fi  
                for arg in $down_list; do
                    if [[ ${compose_list[@]} =~ $arg ]] then
                        docker compose -f $arg down
                    else
                        docker compose -f ${service_to_compose["$arg"]} down $arg
                    fi
                done
                ;;

            -h)
                shift
                echo "Usage: dstop [-s container1 container2 ...] [-d container1 container2 ...]"
                echo "  -s       Stop specified containers. If no containers are provided, stops all running containers."
                echo "  -d       Compose down specified containers. If no containers are provided, composes down all services."
                echo "  -h       Show this help message."
                echo
                echo "Examples:"
                echo "  dstop -s web-app db-server      # Stops web-app and db-server containers."
                echo "  dstop -d                        # Composes down all services."
                echo "  dstop -s web-app -d db-server    # Stops web-app and composes down db-server."
                ;;

            *)
                echo "$1 that isn't an option"
                break
                ;;
        esac
    done
}

dlist() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a)
                shift
                docker ps -a --format "table {{.Names}}\t{{.ID}}\t{{.Status}}"
                return
                ;;
            -f)
                shift
                docker ps --format "table {{.Names}}\t{{.ID}}\t{{.Status}}" --no-trunc
                return
                ;;
            -h)
                shift
                echo "Usage: list out running docker containers, all docker containers, and without truncation"
                echo "-a    This lists all the containers on the system"
                echo "-f    Doesn't truncate the ID or any of the other information"
                echo "Examples:"
                echo "  dlist       # Lists all running containers"
                echo "  dlist -a    # Lists all containers on system"
                echo "  dlist -f    # Does full output without any truncation"
                ;;
            *)
                shift
                echo "$1 that isn't an option"
                echo "-a or -f"
                return 
                ;;
        esac
    done
    docker ps --format "table {{.Names}}\t{{.ID}}\t{{.Status}}"
}

_csv_to_array() {
    local csv_string="$1"

    echo "$csv_string" | tr ',' '\n' | while IFS= read -r element; do
        local trimmed_element=$(echo "$element" | xargs)

        # Only output non-empty elements
        if [[ -n "$trimmed_element" ]]; then
            echo "$trimmed_element"
        fi
    done
}

# Autocomplete Function
_containers() {
    local cur
    cur="${COMP_WORDS[COMP_CWORD]}"

    # Generate the possible completions
    COMPREPLY=($(compgen -W "${complete_list[*]}" -- "$cur"))
}

# Global associative array to map compose files to services
declare -A service_to_compose
declare -A custom_groups
complete_list=()
compose_list=()
service_list=()

# get_services

# Enable running script from anywhere
SCRIPT_DIR="$(pwd)/"

# Path to the file containing the compose files and container names
services_file="${SCRIPT_DIR}scripts-config/services.txt"
config_file="${SCRIPT_DIR}scripts-config/tools.yaml"
build_compose_map

# Set up autocompletion 
complete -F _containers dstart
complete -F _containers dstop

