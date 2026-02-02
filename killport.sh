#!/usr/bin/env bash
set -e

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
    
    if command -v ss &>/dev/null; then
        echo "Using ss command:"
        ss -ltnp "sport = :$port" 2>/dev/null || true
        echo
    fi
    
    if command -v lsof &>/dev/null; then
        echo "Using lsof command:"
        lsof -nP -iTCP:$port -sTCP:LISTEN 2>/dev/null || true
    fi
}

kill_process_on_port() {
    local port=$1 force=$2 verbose=$3
    local pids killed=0
    
    # Get PIDs using lsof
    pids=$(lsof -ti:$port -sTCP:LISTEN 2>/dev/null || true)
    
    if [[ -z "$pids" ]]; then
        [[ "$verbose" == "true" ]] && echo "No processes found on port $port" >&2
        echo "0"
        return 0
    fi
    
    [[ "$verbose" == "true" ]] && echo "Found PIDs: $pids" >&2
    
    for pid in $pids; do
        # Validate PID is a number
        if [[ "$pid" =~ ^[0-9]+$ ]] && [[ "$pid" -gt 1 ]]; then
            # Get process name
            local cmd="unknown"
            if [[ -f "/proc/$pid/comm" ]]; then
                cmd=$(cat "/proc/$pid/comm" 2>/dev/null || echo "unknown")
            elif command -v ps &>/dev/null; then
                cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            fi
            
            echo "Port $port: Killing PID $pid ($cmd)" >&2
            
            if [[ "$force" == "true" ]]; then
                # Force kill with SIGKILL
                if kill -9 "$pid" 2>/dev/null; then
                    killed=$((killed + 1))
                    [[ "$verbose" == "true" ]] && echo "  Killed with SIGKILL" >&2
                else
                    echo "  Failed to kill PID $pid" >&2
                fi
            else
                # Try SIGTERM first
                if kill "$pid" 2>/dev/null 2>&1; then
                    # Wait a bit to see if process exits gracefully
                    sleep 0.1
                    # Check if process is still alive - ignore errors
                    if kill -0 "$pid" 2>/dev/null 2>&1; then
                        echo "  Process still alive, sending SIGKILL" >&2
                        if kill -9 "$pid" 2>/dev/null 2>&1; then
                            killed=$((killed + 1))
                            [[ "$verbose" == "true" ]] && echo "  Killed with SIGKILL" >&2
                        else
                            echo "  Failed to kill with SIGKILL" >&2
                        fi
                    else
                        killed=$((killed + 1))
                        [[ "$verbose" == "true" ]] && echo "  Killed with SIGTERM" >&2
                    fi
                else
                    # If SIGTERM fails, try SIGKILL
                    if kill -9 "$pid" 2>/dev/null 2>&1; then
                        killed=$((killed + 1))
                        [[ "$verbose" == "true" ]] && echo "  Killed with SIGKILL" >&2
                    else
                        echo "  Failed to kill PID $pid" >&2
                    fi
                fi
            fi
        fi
    done
    
    # Return ONLY the number, no other output
    echo "$killed"
}

main() {
    local start_port end_port list_only=false force_kill=false
    local verbose=false
    local killed_total=0
    
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
                verbose=true
                shift
                ;;
            -*)
                echo "Error: Unknown option $1" >&2
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
        echo "Error: No port specified" >&2
        show_help
        exit 1
    fi
    
    # Check if arguments are numbers
    if ! [[ $1 =~ ^[0-9]+$ ]]; then
        echo "Error: '$1' is not a valid port number" >&2
        exit 1
    fi
    
    start_port=$1
    
    if [[ $# -eq 1 ]]; then
        end_port=$start_port
    elif [[ $# -eq 2 ]]; then
        if ! [[ $2 =~ ^[0-9]+$ ]]; then
            echo "Error: '$2' is not a valid port number" >&2
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
        echo "Error: Too many arguments" >&2
        show_help
        exit 1
    fi
    
    # Validate port range
    if [[ $start_port -lt 1 ]] || [[ $end_port -gt 65535 ]]; then
        echo "Error: Ports must be between 1 and 65535" >&2
        exit 1
    fi
    
    if [[ "$list_only" == "true" ]]; then
        for port in $(seq "$start_port" "$end_port"); do
            list_processes "$port"
        done
        exit 0
    fi
    
    [[ "$verbose" == "true" ]] && echo "Searching ports $start_port to $end_port..." >&2
    
    for port in $(seq "$start_port" "$end_port"); do
        local killed
        # Run the function in a subshell and capture ONLY the last line (the count)
        killed=$(kill_process_on_port "$port" "$force_kill" "$verbose" | tail -n1)
        
        # Ensure killed is a number - strip any non-digit characters
        killed=$(echo "$killed" | tr -cd '0-9')
        killed=${killed:-0}
        
        killed_total=$((killed_total + killed))
    done
    
    if [[ $killed_total -eq 0 ]] && [[ "$verbose" == "false" ]]; then
        echo "No processes found on specified ports." >&2
    else
        echo "Done. Total processes killed: $killed_total" >&2
    fi
}

main "$@"
