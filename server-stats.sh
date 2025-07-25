#!/bin/bash

exec > >(tee -a "server-stats-$(date '+%F_%H-%M-%S').log") 2>&1

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

separator="================================================================================"

print_header() {
    echo -e "\n${CYAN}${BOLD}$1${RESET}"
    echo "$separator"
}

print_header "Server Stats Run: $(date '+%F %T')"


# ------------------------ OS Info ------------------------

print_header "OS Info"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "${GREEN}${NAME} ${VERSION}${RESET}"
else
    uname -a
fi

# ------------------------ CPU Uptime ------------------------

# read system_uptime idle_time <<< "$(cat /proc/uptime)"
read system_uptime idle_time < /proc/uptime

total_seconds=${system_uptime%.*}
fractional_part=${system_uptime#*.}

days=$((total_seconds / 86400 ))
hours=$(((total_seconds % 86400) / 3600 ))
minutes=$(((total_seconds % 3600) / 60 ))
seconds=$((total_seconds % 60 ))

print_header "CPU Uptime"
# echo "$days days, $hours hours, $minutes minutes, $seconds seconds"

# Print only non-zero units
[[ $days -gt 0 ]] && echo "$days days"
[[ $hours -gt 0 ]] && echo "$hours hours"
[[ $minutes -gt 0 ]] && echo "$minutes minutes"
[[ $seconds -gt 0 || $fractional_part -ne 0 ]] && echo "$seconds.${fractional_part} seconds"


# ------------------------ CPU Usage ------------------------

top_output=$(top -bn1)

cpu_idle=$(echo "$top_output" | grep "Cpu(s)" | sed 's/.*, *\([0-9.]*\)%* id.*/\1/')
cpu_usage=$(awk -v idle="$cpu_idle" 'BEGIN { printf("%.1f", 100 - idle) }')

print_header "🖥️  CPU Usage"
echo -e "Usage         : ${GREEN}${cpu_usage}%${RESET}"


# ------------------------ Memory Usage ------------------------

read total_memory available_memory <<< $(awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {print t, a}' /proc/meminfo)
used_memory=$((total_memory - available_memory))

used_memory_percent=$(awk -v u=$used_memory -v t=$total_memory 'BEGIN { printf("%.1f", (u / t) * 100) }')
free_memory_percent=$(awk -v a=$available_memory -v t=$total_memory 'BEGIN { printf("%.1f", (a / t) * 100) }')

# Convert from kB to MB 
total_memory_mb=$(awk -v t=$total_memory 'BEGIN { printf("%.1f", t/1024) }')
used_memory_mb=$(awk -v u=$used_memory 'BEGIN { printf("%.1f", u/1024) }')
available_memory_mb=$(awk -v a=$available_memory 'BEGIN { printf("%.1f", a/1024) }')

print_header "🧠 Memory Usage"
printf "Total Memory    : ${YELLOW}%-10s MB${RESET}\n" "$total_memory_mb"
printf "Used Memory     : ${YELLOW}%-10s MB${RESET} (%s%%)\n" "$used_memory_mb" "$used_memory_percent"
printf "Free/Available  : ${YELLOW}%-10s MB${RESET} (%s%%)\n" "$available_memory_mb" "$free_memory_percent"


# ------------------------ Disk Usage ------------------------

df_output=$(df -h /)
size_disk=$(echo "$df_output" | awk 'NR==2 {printf $2}')
# Dont use printf in below line, it doesnt add space
read used_disk available_disk <<< $(echo "$df_output" | awk 'NR==2 {print $3, $4}')

df_output_raw=$(df /)
read size_disk_kb used_disk_kb available_disk_kb <<< $(echo "$df_output_raw" | awk 'NR==2 {print $2, $3, $4}')

if command -v bc &> /dev/null; then
  used_disk_percent=$(echo "scale=2; $used_disk_kb * 100 / $size_disk_kb" | bc)
  available_disk_percent=$(echo "scale=2; $available_disk_kb * 100 / $size_disk_kb" | bc)
else
  used_disk_percent=$(( used_disk_kb * 100 / size_disk_kb ))
  available_disk_percent=$((available_disk_kb * 100 / size_disk_kb))
fi



print_header "💾 Disk Usage"
printf "Disk Size       : ${YELLOW}%-10s${RESET}\n" "$size_disk"
printf "Used Space      : ${YELLOW}%-10s${RESET} (%s%%)\n" "$used_disk" "$used_disk_percent"
printf "Available Space : ${YELLOW}%-10s${RESET} (%s%%)\n" "$available_disk" "$available_disk_percent"


# ------------------------ Top Processes ------------------------

print_header "🔥 Top 5 Processes by CPU"
ps aux --sort=-%cpu | awk 'NR==1 || NR<=6 { printf "%-10s %-6s %-5s %-5s %s\n", $1, $2, $3, $4, $11 }'

print_header "🧠 Top 5 Processes by Memory"
ps aux --sort=-%mem | awk 'NR==1 || NR<=6 { printf "%-10s %-6s %-5s %-5s %s\n", $1, $2, $3, $4, $11 }'

# top_5_processes_by_cpu=$(ps aux --sort -%cpu | head -6)
# top_5_processes_by_memory=$(ps aux --sort -%mem | head -6)

# echo "TOP 5 processes consuming CPU:"
# printf "\n"
# echo "$top_5_processes_by_cpu"

# echo "***************************************************************************************"

# echo "TOP 5 processes consuming Memory:" 
# printf "\n"
# echo "$top_5_processes_by_memory"


# ------------------------ Users currently Logged In ------------------------

print_header "Users currently Logged In"
users

users_info_more=false

print_header "More info on Logged In Users"

if [[ "$users_info_more" == false ]]; then
  echo "USER     TTY          LOGIN-TIME        FROM"
  who
else
  w
fi


# ------------------------ Failed Log In Attempts ------------------------

# Resources
# https://www.tecmint.com/find-failed-ssh-login-attempts-in-linux/

# Check which log file exists in the system for authentication logs
if [ -f /var/log/auth.log ]; then
  # Debian/Ubuntu
  # grep "Failed password" /var/log/auth.log | awk '{print $11}' | uniq -c | sort -nr
  print_header "Top IPs causing failed logins:"
  grep "Failed password" /var/log/auth.log | awk '{for(i=1;i<=NF;i++){if($i=="from"){print $(i+1)}}}' | sort | uniq -c | sort -nr
  print_header "Logs of Failed Log In Attempts"
  grep -E "Failed|Failure" /var/log/auth.log
elif [ -f /var/log/secure ]; then
  # RHEL/CentOS
  # grep "Failed password" /var/log/secure | awk '{print $11}' | uniq -c | sort -nr
  print_header "Top IPs causing failed logins:"
  grep "Failed password" /var/log/auth.log | awk '{for(i=1;i<=NF;i++){if($i=="from"){print $(i+1)}}}' | sort | uniq -c | sort -nr
  print_header "Logs of Failed Log In Attempts"
  grep -E "Failed|Failure" /var/log/secure
else
  echo "Sorry, no recognised authentication log file found"
fi
