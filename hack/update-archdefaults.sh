#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALUES_ROOT="$BASE_DIR/components/multi-platform-controller"

remove_archdefaults() {
  local file="$1"
  awk '
    BEGIN { skip=0 }
    /^archDefaults:[[:space:]]*$/ { skip=1; next }
    skip==1 && $0 !~ /^[[:space:]]/ { skip=0 }
    skip==1 { next }
    { print }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

infer_archdefaults() {
  # Prints: arm_ami|arm_key|arm_sg|arm_sub|amd_ami|amd_key|amd_sg|amd_sub
  local file="$1"
  awk '
    BEGIN { within=0; currentArch=""; armAmi=""; armKey=""; armSg=""; armSubnet=""; amdAmi=""; amdKey=""; amdSg=""; amdSubnet="" }
    /^dynamicConfigs:[[:space:]]*$/ { within=1; next }
    within && $0 !~ /^[[:space:]]/ { within=0 }
    within && $0 ~ /^[ ]{2}(linux(-[a-z0-9]+)*-arm64|linux-arm64):[[:space:]]*$/ { currentArch="arm"; next }
    within && $0 ~ /^[ ]{2}(linux(-[a-z0-9]+)*-amd64|linux-amd64):[[:space:]]*$/ { currentArch="amd"; next }
    within && currentArch=="arm" && armAmi==""  && $0 ~ /^[ ]{4}ami:[[:space:]]*"[^"]+"/ { s=$0; gsub(/^[^:]*:[[:space:]]*"/,"",s); gsub(/"$/,"",s); armAmi=s; next }
    within && currentArch=="arm" && armKey==""  && $0 ~ /^[ ]{4}key-name:[[:space:]]*"[^"]+"/ { s=$0; gsub(/^[^:]*:[[:space:]]*"/,"",s); gsub(/"$/,"",s); armKey=s; next }
    within && currentArch=="arm" && armSg=="" && $0 ~ /^[ ]{4}security-group-id:[[:space:]]*"[^"]+"/ { s=$0; gsub(/^[^:]*:[[:space:]]*"/,"",s); gsub(/"$/,"",s); armSg=s; next }
    within && currentArch=="arm" && armSubnet==""&& $0 ~ /^[ ]{4}subnet-id:[[:space:]]*"[^"]+"/ { s=$0; gsub(/^[^:]*:[[:space:]]*"/,"",s); gsub(/"$/,"",s); armSubnet=s; next }
    within && currentArch=="amd" && amdAmi==""  && $0 ~ /^[ ]{4}ami:[[:space:]]*"[^"]+"/ { s=$0; gsub(/^[^:]*:[[:space:]]*"/,"",s); gsub(/"$/,"",s); amdAmi=s; next }
    within && currentArch=="amd" && amdKey==""  && $0 ~ /^[ ]{4}key-name:[[:space:]]*"[^"]+"/ { s=$0; gsub(/^[^:]*:[[:space:]]*"/,"",s); gsub(/"$/,"",s); amdKey=s; next }
    within && currentArch=="amd" && amdSg=="" && $0 ~ /^[ ]{4}security-group-id:[[:space:]]*"[^"]+"/ { s=$0; gsub(/^[^:]*:[[:space:]]*"/,"",s); gsub(/"$/,"",s); amdSg=s; next }
    within && currentArch=="amd" && amdSubnet==""&& $0 ~ /^[ ]{4}subnet-id:[[:space:]]*"[^"]+"/ { s=$0; gsub(/^[^:]*:[[:space:]]*"/,"",s); gsub(/"$/,"",s); amdSubnet=s; next }
    END { printf("%s|%s|%s|%s|%s|%s|%s|%s\n", armAmi, armKey, armSg, armSubnet, amdAmi, amdKey, amdSg, amdSubnet) }
  ' "$file"
}

insert_archdefaults() {
  local file="$1"
  local arm_ami="$2" arm_key="$3" arm_sg="$4" arm_sub="$5"
  local amd_ami="$6" amd_key="$7" amd_sg="$8" amd_sub="$9"
  local insline
  insline=$(grep -n '^dynamicConfigs:' "$file" | head -1 | cut -d: -f1 || true)
  if [[ -z "$insline" ]]; then
    insline=$(( $(wc -l < "$file") + 1 ))
  fi
  awk -v ins="$insline" \
      -v aami="$arm_ami" -v akey="$arm_key" -v asg="$arm_sg" -v asub="$arm_sub" \
      -v dami="$amd_ami" -v dkey="$amd_key" -v dsg="$amd_sg" -v dsub="$amd_sub" '
    NR==ins {
      print ""
      print "archDefaults:"
      print "  arm64:"
      if (aami!="") print "    ami: \"" aami "\""
      if (akey!="") print "    key-name: \"" akey "\""
      if (asg!="")  print "    security-group-id: \"" asg "\""
      if (asub!="") print "    subnet-id: \"" asub "\""
      print "  amd64:"
      if (dami!="") print "    ami: \"" dami "\""
      if (dkey!="") print "    key-name: \"" dkey "\""
      if (dsg!="")  print "    security-group-id: \"" dsg "\""
      if (dsub!="") print "    subnet-id: \"" dsub "\""
    }
    { print }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

clean_redundant() {
  local file="$1"
  local arm_ami="$2" arm_key="$3" arm_sg="$4" arm_sub="$5"
  local amd_ami="$6" amd_key="$7" amd_sg="$8" amd_sub="$9"
  awk -v aami="$arm_ami" -v akey="$arm_key" -v asg="$arm_sg" -v asub="$arm_sub" \
      -v dami="$amd_ami" -v dkey="$amd_key" -v dsg="$amd_sg" -v dsub="$amd_sub" '
    BEGIN { within=0; currentArch="" }
    /^dynamicConfigs:[[:space:]]*$/ { within=1; print; next }
    within && $0 !~ /^[[:space:]]/ { within=0 }
    within && $0 ~ /^[ ]{2}(linux(-[a-z0-9]+)*-arm64|linux-arm64):[[:space:]]*$/ { currentArch="arm"; print; next }
    within && $0 ~ /^[ ]{2}(linux(-[a-z0-9]+)*-amd64|linux-amd64):[[:space:]]*$/ { currentArch="amd"; print; next }
    within && currentArch=="arm" && $0 ~ /^[ ]{4}ami:[[:space:]]*"[^"]+"/ { v=$0; gsub(/^[^:]*:[[:space:]]*"/,"",v); gsub(/"$/,"",v); if (aami!="" && v==aami) next }
    within && currentArch=="arm" && $0 ~ /^[ ]{4}key-name:[[:space:]]*"[^"]+"/ { v=$0; gsub(/^[^:]*:[[:space:]]*"/,"",v); gsub(/"$/,"",v); if (akey!="" && v==akey) next }
    within && currentArch=="arm" && $0 ~ /^[ ]{4}security-group-id:[[:space:]]*"[^"]+"/ { v=$0; gsub(/^[^:]*:[[:space:]]*"/,"",v); gsub(/"$/,"",v); if (asg!="" && v==asg) next }
    within && currentArch=="arm" && $0 ~ /^[ ]{4}subnet-id:[[:space:]]*"[^"]+"/ { v=$0; gsub(/^[^:]*:[[:space:]]*"/,"",v); gsub(/"$/,"",v); if (asub!="" && v==asub) next }
    within && currentArch=="amd" && $0 ~ /^[ ]{4}ami:[[:space:]]*"[^"]+"/ { v=$0; gsub(/^[^:]*:[[:space:]]*"/,"",v); gsub(/"$/,"",v); if (dami!="" && v==dami) next }
    within && currentArch=="amd" && $0 ~ /^[ ]{4}key-name:[[:space:]]*"[^"]+"/ { v=$0; gsub(/^[^:]*:[[:space:]]*"/,"",v); gsub(/"$/,"",v); if (dkey!="" && v==dkey) next }
    within && currentArch=="amd" && $0 ~ /^[ ]{4}security-group-id:[[:space:]]*"[^"]+"/ { v=$0; gsub(/^[^:]*:[[:space:]]*"/,"",v); gsub(/"$/,"",v); if (dsg!="" && v==dsg) next }
    within && currentArch=="amd" && $0 ~ /^[ ]{4}subnet-id:[[:space:]]*"[^"]+"/ { v=$0; gsub(/^[^:]*:[[:space:]]*"/,"",v); gsub(/"$/,"",v); if (dsub!="" && v==dsub) next }
    { print }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

export -f remove_archdefaults infer_archdefaults insert_archdefaults clean_redundant

find "$VALUES_ROOT" -type f -name 'values-*.yaml' ! -path '*/development/*' | while read -r f; do
  echo "[archDefaults] Processing $f"
  remove_archdefaults "$f"
  IFS='|' read -r arm_ami arm_key arm_sg arm_sub amd_ami amd_key amd_sg amd_sub < <(infer_archdefaults "$f")
  insert_archdefaults "$f" "$arm_ami" "$arm_key" "$arm_sg" "$arm_sub" "$amd_ami" "$amd_key" "$amd_sg" "$amd_sub"
  clean_redundant "$f" "$arm_ami" "$arm_key" "$arm_sg" "$arm_sub" "$amd_ami" "$amd_key" "$amd_sg" "$amd_sub"
done

echo "archDefaults inserted and redundant fields cleaned."


