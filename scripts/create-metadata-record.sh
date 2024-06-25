#!/usr/bin/env bash

img_rcd_file=record.yaml
app_deploy_RECORD_FILE=app.yml
json_file=temp.json
output_file=output.txt
CONFIG_FILE=mktemp
CERC_IPFS_HOST_ENDPOINT=http://138.197.130.188:5001
CERC_IPFS_SERVER_ENDPOINT=http://138.197.130.188:33597
image_file=examples/image.jpeg


rm -f $img_rcd_file
rm -f $json_file
rm -f $output_file
rm -f $CONFIG_FILE

# Use exitfool to extract photo metadata
exiftool $image_file -json > $json_file

# Iterate over the array using jq
jq -c '.[]' "$json_file" | while IFS= read -r item; do
  # Iterate over the key-value pairs dynamically
  echo "$item" | jq -r 'to_entries[] | "\(.key) \(.value)"' | while IFS= read -r line; do
    key=$(echo "$line" | awk '{print $1}')
    # surround the value with single quotes to make valid YAML
    value=$(echo "$line" | awk '{$1=""; print $0}')
    #value=$(echo "$line" | awk '{$1=""; print $0}' | awk '{print "\x27" $0 "\x27"}')
    # write each record with 4 spaces for record.yml formatting
    echo "    $key: $value" >> $output_file
  done
done

meta_data=$(cat output.txt)
echo "Example image metadata ${meta_data}"

echo "Using IPFS endpoint ${CERC_IPFS_HOST_ENDPOINT}"
echo "Using IPFS server endpoint ${CERC_IPFS_SERVER_ENDPOINT}"
ipfs_host_endpoint=${CERC_IPFS_HOST_ENDPOINT}
ipfs_server_endpoint=${CERC_IPFS_SERVER_ENDPOINT}

# Upload the image to IPFS
echo "Uploading glob file to ${ipfs_host_endpoint}"
upload_response=$(curl -X POST -F file=@${image_file} ${ipfs_host_endpoint}/api/v0/add)
image_cid=$(echo "$upload_response" | grep -o '"Hash":"[^"]*' | sed 's/"Hash":"//')

image_url="${ipfs_server_endpoint}/ipfs/${image_cid}?filename=${image_file}"

echo "Glob file uploaded to IFPS:"
echo "{ cid: ${image_cid}, filename: ${image_file} }"
echo "{ url: ${image_url} }"

cat <<EOF > "$img_rcd_file"
record:
  type: GeneralRecord
  name: image-registration-record
  version: 0.0.2
  value: "cute-rare-animal"
  category: birbit
  tags:
    - golden
    - pheasant
    - trespassing
    - ${image_url}
  meta:
    note: "test"
EOF
# the metadata needs massaging in order to be the correct yaml format
# leaving it out for now
#$meta_data


cat <<EOF > "$CONFIG_FILE"
services:
  cns:
    restEndpoint: '${CERC_REGISTRY_REST_ENDPOINT:-http://console.laconic.com:1317}'
    gqlEndpoint: '${CERC_REGISTRY_GQL_ENDPOINT:-http://console.laconic.com:9473/api}'
    chainId: ${CERC_REGISTRY_CHAIN_ID:-laconic_9000-1}
    gas: 550000
    fees: 200000aphoton
EOF

cat $img_rcd_file

IMG_RECORD_ID=$(laconic -c $CONFIG_FILE cns record publish --filename $img_rcd_file --user-key "${CERC_REGISTRY_USER_KEY}" --bond-id ${CERC_REGISTRY_BOND_ID} | jq -r '.id')

echo "img rcd id"
echo $IMG_RECORD_ID

###########
# next, deploy a webapp with a "view"

#
rcd_name=$(jq -r '.name' package.json | sed 's/null//' | sed 's/^@//')
rcd_app_version=$(jq -r '.version' package.json | sed 's/null//')

if [ -z "$CERC_REGISTRY_APP_CRN" ]; then
  authority=$(echo "$rcd_name" | cut -d'/' -f1 | sed 's/@//')
  app=$(echo "$rcd_name" | cut -d'/' -f2-)
  CERC_REGISTRY_APP_CRN="crn://$authority/applications/$app"
fi

APP_RECORD=$(laconic -c $CONFIG_FILE cns name resolve "$CERC_REGISTRY_APP_CRN" | jq '.[0]')
if [ -z "$APP_RECORD" ] || [ "null" == "$APP_RECORD" ]; then
  echo "No record found for $CERC_REGISTRY_APP_CRN."
  exit 1
fi

#example of a view, constructed seperately
geojson_url="http://geojson.io/#data=data:text/x-url,https%3A%2F%2Fgist.githubusercontent.com%2Fzramsay%2F7cdcd9f50c1d2930f1aeb9073cae2661%2Fraw%2F63b021eebb72ec2b13f327ba67f585ccf9b0b6e5%2Ftest.geojson"


cat <<EOF | sed '/.*: ""$/d' > "$app_deploy_RECORD_FILE"
record:
  type: ApplicationDeploymentRequest
  version: 1.0.0
  name: "$rcd_name@$rcd_app_version"
  application: "$CERC_REGISTRY_APP_CRN@$rcd_app_version"
  dns: "$CERC_REGISTRY_DEPLOYMENT_SHORT_HOSTNAME"
  deployment: "$CERC_REGISTRY_DEPLOYMENT_CRN"
  config:
    env:
      CERC_TEST_WEBAPP_CONFIG1: "$image_url"
      CERC_TEST_WEBAPP_CONFIG2: "$geojson_url"
      CERC_WEBAPP_DEBUG: "$rcd_app_version"
  meta:
    note: "Added by CI @ `date`"
    repository: "`git remote get-url origin`"
    repository_ref: "${GITHUB_SHA:-`git log -1 --format="%H"`}"
EOF

cat $app_deploy_RECORD_FILE

APP_RECORD_ID=$(laconic -c $CONFIG_FILE cns record publish --filename $app_deploy_RECORD_FILE --user-key "${CERC_REGISTRY_USER_KEY}" --bond-id ${CERC_REGISTRY_BOND_ID} | jq -r '.id')
echo $APP_RECORD_ID
