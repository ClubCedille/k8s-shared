#!/bin/bash

EXTERNAL_SITES_YAML=/tmp/nextcloud-external-sites.yaml
YAML_FILE=/tmp/clubs.yaml

apt update
apt install -y jq yq

# Configure cron
php /var/www/html/occ background:cron

# install apps

php /var/www/html/occ app:install user_oidc
php /var/www/html/occ app:install richdocuments
php /var/www/html/occ app:install groupfolders
php /var/www/html/occ app:install previewgenerator
php /var/www/html/occ app:install whiteboard
php /var/www/html/occ app:install drawio
php /var/www/html/occ app:install external
php /var/www/html/occ app:install notes

# Authentik config
php /var/www/html/occ user_oidc:provider "Authentik" \
    --clientid="$AUTHENTIK_CLIENT_ID" \
    --clientsecret="$AUTHENTIK_CLIENT_SECRET" \
    --discoveryuri="$AUTHENTIK_CONFIG_URL" \
    --group-provisioning=1 \
    --bearer-provisioning=1 \
    --unique-uid=0 \
    --group-whitelist-regex="^(admin|club-.+|exec-.+)$" \
    --group-restrict-login-to-whitelist=1 \
    --send-id-token-hint=1 \
    --check-bearer=1
php /var/www/html/occ config:app:set user_oidc allow_multiple_user_backends --value=0

# Collabora config
php /var/www/html/occ config:app:set richdocuments wopi_url --value https://collabora-nextcloud.etsmtl.club
php /var/www/html/occ config:app:set richdocuments wopi_allowlist --value 10.244.0.0/16
php /var/www/html/occ config:app:set richdocuments doc_format --value ooxml
php /var/www/html/occ richdocuments:activate-config

# Set maintenance window from 1 am to 5 am
php /var/www/html/occ config:system:set maintenance_window_start --value="1" --type=integer

# Set default storage quota to 0
php /var/www/html/occ config:app:set files default_quota --value="0 B"

# Theming

THEME_COLOR="#E40032"
THEME_NAME="Nextcloud ÉTS"
THEME_LOGO_URL="https://www.etsmtl.ca/assets/img/ets.svg"
THEME_BACKGROUND_URL="https://www.etsmtl.ca/uploads/ETS_50e_ext%C3%A9rieur-ID-1068690.jpg"

php /var/www/html/occ theming:config primary_color "${THEME_COLOR}"
php /var/www/html/occ theming:config name "${THEME_NAME}"
mkdir /pics
ext="${THEME_LOGO_URL##*.}"
curl -o /pics/logo.${ext} "${THEME_LOGO_URL}"
php /var/www/html/occ theming:config logo /pics/logo.${ext}
ext="${THEME_BACKGROUND_URL##*.}"
curl -o /pics/background.${ext} "${THEME_BACKGROUND_URL}"
php /var/www/html/occ theming:config background /pics/background.${ext}
php /var/www/html/occ theming:config disable-user-theming 1

# Current groups
groups_current=$(php /var/www/html/occ group:list --output=json | jq -r 'keys | .[]')
# Extract 'name' from YAML
yaml_names=$(yq -r '.[].name' "$YAML_FILE")
# Extract 'mount_point' from JSON
json_api=$(php /var/www/html/occ groupfolders:list --output=json)
json_mounts=$(echo "$json_api" | jq -r '.[].mount_point')

# Compare
for name in $yaml_names; do
  if ! grep -qx "club-$name" <<< "$groups_current"; then
    echo "Creating groups for $name"
    php /var/www/html/occ group:add club-$name
    php /var/www/html/occ group:add exec-$name
  fi
  target_quota=$(yq ".[] | select(.name == \"$name\") | .quota" "$YAML_FILE")
  target_quota=$((target_quota * 1024 * 1024 * 1024))
  if ! grep -qx "$name" <<< "$json_mounts"; then
    echo "Creating groupfolder for $name"
    folder_id=$(php /var/www/html/occ groupfolders:create "${name}")
    echo Folder ID: $folder_id
    php /var/www/html/occ groupfolders:group  "${folder_id}" "club-${name}" read write share delete
    php /var/www/html/occ groupfolders:group  "${folder_id}" "exec-${name}" read write share delete
    php /var/www/html/occ groupfolders:permissions "${folder_id}" --enable
    php /var/www/html/occ groupfolders:permissions "${folder_id}" -m -g exec-${name}
    php /var/www/html/occ groupfolders:permissions "${folder_id}" -g club-cedille / +read +write +create +delete +share
    php /var/www/html/occ groupfolders:permissions "${folder_id}" -g exec-cedille / +read +write +create +delete +share
    php /var/www/html/occ groupfolders:quota  "${folder_id}" "${target_quota}"
  elif  [[ $target_quota != $(echo "$json_api" | jq ".[] | select(.mount_point == \"$name\") | .quota") ]]; then
    echo "Updating groupfolder quota for $name"
    folder_id=$(echo "$json_api" | jq -r ".[] | select(.mount_point == \"$name\") | .id")
    php /var/www/html/occ groupfolders:quota  "${folder_id}" "${target_quota}"
  fi
done


# External sites

# EXTERNAL_SITES_YAML=apps/nextcloud/job-files/external-sites.yaml
external_sites_ids=$(yq -r '.[].id' "$EXTERNAL_SITES_YAML")
appdata=$(ls /var/www/html/data/ | grep appdata_)
EXTERNAL_SITES_JSON="{}"

for id in $external_sites_ids; do

  external_site_name=$(yq -r ".[] | select(.id == $id) | .name" "$EXTERNAL_SITES_YAML")
  external_site_url=$(yq -r ".[] | select(.id == $id) | .url" "$EXTERNAL_SITES_YAML")
  external_site_lang=$(yq -r ".[] | select(.id == $id) | .lang" "$EXTERNAL_SITES_YAML")
  external_site_type=$(yq -r ".[] | select(.id == $id) | .type" "$EXTERNAL_SITES_YAML")
  external_site_device=$(yq -r ".[] | select(.id == $id) | .device" "$EXTERNAL_SITES_YAML")
  external_site_redirect=$(yq -r ".[] | select(.id == $id) | .redirect" "$EXTERNAL_SITES_YAML")

  external_site_logo_url=$(yq -r ".[] | select(.id == $id) | .icon_url" "$EXTERNAL_SITES_YAML")
  ext="${external_site_logo_url##*.}"
  curl -o /var/www/html/data/$appdata/external/icons/$external_site_name.$ext "$external_site_logo_url"
  
  echo $external_site_name
  EXTERNAL_SITES_JSON=$(echo "$EXTERNAL_SITES_JSON" | jq ".\"$id\" = {
    \"id\": $id,
    \"name\": \"$external_site_name\",
    \"url\": \"$external_site_url\",
    \"lang\": \"$external_site_lang\",
    \"type\": \"$external_site_type\",
    \"device\": \"$external_site_device\",
    \"icon\": \"$external_site_name.$ext\",
    \"groups\": $(yq -r "[.[] | select(.external_sites[]? == \"$external_site_name\") | \"club-\" + .name]" "$YAML_FILE"),
    \"redirect\": $external_site_redirect
  }")
done

echo "$EXTERNAL_SITES_JSON"
php /var/www/html/occ config:app:set external sites --value="${EXTERNAL_SITES_JSON}"
