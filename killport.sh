#!/usr/bin/env bash
set -eu

show_help() {
    cat << EOF
Kill processes listening on specified port(s).

Usage: killport [OPTIONS] <PORT> [END_PORT]
       killport <PORT>
       killport <START_PORT> <END_PORT>

Options:
  -h, --help     Show this help message
  -l, --list     List processes without killing
  -f, --force    Force kill with SIGKILL (default: SIGTERM)
  -v, --verbose  Show detailed information

Examples:
  killport 3000          # Kill process on port 3000
  killport 3000 3010     # Kill processes on ports 3000-3010
  killport -l 3000       # List process on port 3000
  killport -f 8080       # Force kill process on port 8080
EOF
}

list_processes() {
    local port=$1
    echo "=== Processes on port $port ==="
    
    # Try ss first (faster)
    if command -v ss &>/dev/null; then
        echo "Using ss command:"
        ss -ltnp "sport = :$port" 2>/dev/null || true
        echo
    fi
    
    # Then lsof (more detailed)
    if command -v lsof &>/dev/null; then
        echo "Using lsof command:"
        lsof -nP -iTCP:$port -sTCP:LISTEN 2>/dev/null || true
    fi
}

kill_process_on_port() {
    local port=$1 force=$2
    local pids killed=0
    
    # Method 1: Using lsof (more reliable)
    if command -v lsof &>/dev/null; then
        pids=$(lsof -ti:$port 2>/dev/null)
        [[ -n "$pids" ]] && [[ "$VERBOSE" == "true" ]] && echo "Found PIDs using lsof: $pids"
    fi
    
    # Method 2: Using ss as fallback (different extraction method)
    if [[ -z "$pids" ]] && command -v ss &>/dev/null; then
        pids=$(ss -ltnp "sport = :$port" 2>/dev/null | grep -Eo 'pid=[0-9]+' | cut -d= -f2 | sort -u)
        [[ -n "$pids" ]] && [[ "$VERBOSE" == "true" ]] && echo "Found PIDs using ss: $pids"
    fi
    
    # Method 3: Alternative ss extraction (more robust)
    if [[ -z "$pids" ]] && command -v ss &>/dev/null; then
        pids=$(ss -ltpn "sport = :$port" 2>/dev/null | awk 'NR>1 {print $6}' | cut -d= -f2 | cut -d, -f1 | sort -u)
        [[ -n "$pids" ]] && [[ "$VERBOSE" == "true" ]] && echo "Found PIDs using ss (alternative): $pids"
    fi
    
    # Method 4: Using netstat as last resort
    if [[ -z "$pids" ]] && command -v netstat &>/dev/null; then
        pids=$(netstat -ltnp 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d/ -f1 | sort -u)
        [[ -n "$pids" ]] && [[ "$VERBOSE" == "true" ]] && echo "Found PIDs using netstat: $pids"
    fi
    
    # Remove empty lines and duplicates
    pids=$(echo "$pids" | tr ' ' '\n' | grep -v '^$' | sort -u)
    
    if [[ -z "$pids" ]]; then
        [[ "$VERBOSE" == "true" ]] && echo "No processes found on port $port"
        return 0
    fi
    
    for pid in $pids; do
        # Validate PID is a number and not system process
        if [[ "$pid" =~ ^[0-9]+$ ]] && [[ "$pid" -gt 1 ]]; then
            # Get process info
            local cmd=""
            if [[ -f "/proc/$pid/comm" ]]; then
                cmd=$(cat "/proc/$pid/comm" 2>/dev/null || echo "unknown")
            elif command -v ps &>/dev/null; then
                cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            fi
            
            echo "Port $port: Killing PID $pid ($cmd)"
            
            if [[ "$force" == "true" ]]; then
                # Try SIGKILL directly
                if kill -9 "$pid" 2>/dev/null; then
                    killed=$((killed + 1))
                    [[ "$VERBOSE" == "true" ]] && echo "  Successfully killed PID $pid with SIGKILL"
                else
                    echo "  Warning: Failed to kill PID $pid"
                fi
            else
                # Try SIGTERM first, then SIGKILL
                if kill "$pid" 2>/dev/null; then
                    # Wait a bit to see if process exits gracefully
                    sleep 0.2
                    if kill -0 "$pid" 2>/dev/null; then
                        echo "  Process $pid still alive, sending SIGKILL"
                        kill -9 "$pid" 2>/dev/null && killed=$((killed + 1))
                    else
                        killed=$((killed + 1))
                        [[ "$VERBOSE" == "true" ]] && echo "  Successfully killed PID $pid with SIGTERM"
                    fi
                else
                    # If SIGTERM fails, try SIGKILL
                    kill -9 "$pid" 2>/dev/null && killed=$((killed + 1)) || \
                        echo "  Failed to kill $pid"
                fi
            fi
        fi
    done
    
    echo "$killed"
}

main() {
    local start_port end_port list_only=false force_kill=false
    VERBOSE=false
    KILLED_TOTAL=0
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list)
                list_only=true
                shift
                ;;
            -f|--force)
                force_kill=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -*)
                echo "Error: Unknown option $1"
                show_help
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Validate arguments
    if [[ $# -eq 0 ]]; then
        echo "Error: No port specified"
        show_help
        exit 1
    fi
    
    # Check if arguments are numbers
    if ! [[ $1 =~ ^[0-9]+$ ]]; then
        echo "Error: '$1' is not a valid port number"
        exit 1
    fi
    
    start_port=$1
    
    if [[ $# -eq 1 ]]; then
        end_port=$start_port
    elif [[ $# -eq 2 ]]; then
        if ! [[ $2 =~ ^[0-9]+$ ]]; then
            echo "Error: '$2' is not a valid port number"
            exit 1
        fi
        end_port=$2
        
        # Ensure start <= end
        if [[ $start_port -gt $end_port ]]; then
            local temp=$start_port
            start_port=$end_port
            end_port=$temp
        fi
    else
        echo "Error: Too many arguments"
        show_help
        exit 1
    fi
    
    # Validate port range
    if [[ $start_port -lt 1 ]] || [[ $end_port -gt 65535 ]]; then
        echo "Error: Ports must be between 1 and 65535"
        exit 1
    fi
    
    if [[ "$list_only" == "true" ]]; then
        for port in $(seq "$start_port" "$end_port"); do
            list_processes "$port"
        done
        exit 0
    fi
    
    # Kill processes
    echo "Searching ports $start_port to $end_port..."
    
    for port in $(seq "$start_port" "$end_port"); do
        killed=$(kill_process_on_port "$port" "$force_kill")
        KILLED_TOTAL=$((KILLED_TOTAL + killed))
    done
    
    if [[ $KILLED_TOTAL -eq 0 ]] && [[ "$VERBOSE" == "false" ]]; then
        echo "No processes found on specified ports."
    else
        echo "Done. Total processes killed: $KILLED_TOTAL"
    fi
}

main "$@"
