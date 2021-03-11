#!/usr/bin/env bash

random_str() {
    local length=$1
    cat /dev/urandom | tr -dc 'a-z' | fold -w "$length" | head -n 1
    return 0
}

DEPLOYMENT_PREFIX=${DEPLOYMENT_PREFIX:-}
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID:-}
AZURE_RESOURCE_GROUP_NAME=${AZURE_RESOURCE_GROUP_NAME:-}
AZURE_RESOURCE_GROUP_LOCATION=${AZURE_RESOURCE_GROUP_LOCATION:-}

if [[ -z "$DEPLOYMENT_PREFIX" ]]
then
    echo "No [DEPLOYMENT_PREFIX] specified, generating one."
    DEPLOYMENT_PREFIX=$(random_str 3)
    echo "[DEPLOYMENT_PREFIX] is set to \"$DEPLOYMENT_PREFIX\"."
fi
if [[ -z "$AZURE_SUBSCRIPTION_ID" ]]
then
    echo "No Azure subscription id [AZURE_SUBSCRIPTION_ID] specified."
    exit 1
fi
if [[ -z "$AZURE_RESOURCE_GROUP_NAME" ]]
then
    echo "No Azure resource group [AZURE_RESOURCE_GROUP_NAME] specified."
    exit 1
fi
if [[ -z "$AZURE_RESOURCE_GROUP_LOCATION" ]]
then
    echo "No Azure resource group [AZURE_RESOURCE_GROUP_LOCATION] specified."
    exit 1
fi

# Login to Azure and select the subscription
if ! AZURE_USERNAME=$(az account show --query user.name);
then
    echo "No Azure account logged in, now trying to log in."
    az login
else
    echo "Logged in as $AZURE_USERNAME, set the active subscription to \"$AZURE_SUBSCRIPTION_ID\""
    az account set -s "$AZURE_SUBSCRIPTION_ID"
fi

# Check the resource group and region
RG_EXISTS=$(az group exists --resource-group "$AZURE_RESOURCE_GROUP_NAME")
if [[ $RG_EXISTS == "false" ]]
then
    echo "Creating resource group $AZURE_RESOURCE_GROUP_NAME in $AZURE_RESOURCE_GROUP_LOCATION."
    az group create --location "$AZURE_RESOURCE_GROUP_LOCATION" --resource-group "$AZURE_RESOURCE_GROUP_NAME"
else
    echo "Resource group $AZURE_RESOURCE_GROUP_NAME exists in $AZURE_RESOURCE_GROUP_LOCATION."
    RG_LOCATION=$(az group show --resource-group "$AZURE_RESOURCE_GROUP_NAME" --query location)
    if [[ "$RG_LOCATION" != "\"$AZURE_RESOURCE_GROUP_LOCATION\"" ]]
    then
        echo "Resource group $AZURE_RESOURCE_GROUP_NAME is located in $RG_LOCATION, not \"$AZURE_RESOURCE_GROUP_LOCATION\""
    fi
fi

# Validate the ARM templates (Jacob)

tagValues="{}"

disablePublicIp=false
adbWorkspaceLocation="$AZURE_RESOURCE_GROUP_LOCATION"
adbWorkspaceName="${DEPLOYMENT_PREFIX}adb01"
adbWorkspaceSkuTier="standard"

echo "Validating parameters for Azure Databricks..."
if ! az deployment group validate \
    --resource-group "$AZURE_RESOURCE_GROUP_NAME" \
    --template-file ./databricks/workspace.template.json \
    --parameters \
        disablePublicIp="$disablePublicIp" \
        adbWorkspaceLocation="$adbWorkspaceLocation" \
        adbWorkspaceName="$adbWorkspaceName" \
        adbWorkspaceSkuTier="$adbWorkspaceSkuTier" \
        tagValues="$tagValues";
then
    echo "Validation error for Azure Databricks, please see the error above."
    exit 1
else
    echo "Azure Databricks parameters are valid."
fi

keyVaultName="${DEPLOYMENT_PREFIX}akv01"
keyVaultLocation="$AZURE_RESOURCE_GROUP_LOCATION"
enabledForDeployment="false"
enabledForTemplateDeployment="false"
tenantId="$(az account show --query "tenantId" --output tsv)"
objectId="$(az ad signed-in-user show --query "objectId" --output tsv)"
keyVaultSkuTier="Standard"

echo "Validating parameters for Azure Key Vault..."
if ! az deployment group validate \
    --resource-group "$AZURE_RESOURCE_GROUP_NAME" \
    --template-file ./keyvault/keyvault.template.json \
    --parameters \
        keyVaultName="$keyVaultName" \
        keyVaultLocation="$keyVaultLocation" \
        enabledForDeployment="$enabledForDeployment" \
        enabledForTemplateDeployment="$enabledForTemplateDeployment" \
        tenantId="$tenantId" \
        objectId="$objectId" \
        keyVaultSkuTier="$keyVaultSkuTier" \
        tagValues="$tagValues";
then
    echo "Validation error for Azure Key Vault, please see the error above."
    exit 1
else
    echo "Azure Key Vault parameters are valid."
fi

storageAccountName="${DEPLOYMENT_PREFIX}asa01"
storageAccountSku="Standard_LRS"
storageAccountSkuTier="Standard"
storageAccountLocation="$AZURE_RESOURCE_GROUP_LOCATION"
encryptionEnabled="true"

echo "Validating parameters for Azure Storage Account..."
if ! az deployment group validate \
    --resource-group "$AZURE_RESOURCE_GROUP_NAME" \
    --template-file ./storageaccount/storageaccount.template.json \
    --parameters \
        storageAccountName="$storageAccountName" \
        storageAccountSku="$storageAccountSku" \
        storageAccountSkuTier="$storageAccountSkuTier" \
        storageAccountLocation="$storageAccountLocation" \
        encryptionEnabled="$encryptionEnabled";
then
    echo "Validation error for Azure Storage Account, please see the error above."
    exit 1
else
    echo "Azure Storage Account parameters are valid."
fi

# Deploy ARM templates (Jacob)
echo "Deploying Azure Databricks..."
if ! az deployment group create \
    --resource-group "$AZURE_RESOURCE_GROUP_NAME" \
    --template-file ./databricks/workspace.template.json \
    --parameters \
        disablePublicIp="$disablePublicIp" \
        adbWorkspaceLocation="$adbWorkspaceLocation" \
        adbWorkspaceName="$adbWorkspaceName" \
        adbWorkspaceSkuTier="$adbWorkspaceSkuTier" \
        tagValues="$tagValues";
then
    echo "Deployment of Azure Databricks failed, please see the error above."
    exit 1
else
    echo "Deployment of Azure Databricks succeeded."
fi

echo "Deploying Azure Key Vault..."
if ! az deployment group create \
    --resource-group "$AZURE_RESOURCE_GROUP_NAME" \
    --template-file ./keyvault/keyvault.template.json \
    --parameters \
        keyVaultName="$keyVaultName" \
        keyVaultLocation="$keyVaultLocation" \
        enabledForDeployment="$enabledForDeployment" \
        enabledForTemplateDeployment="$enabledForTemplateDeployment" \
        tenantId="$tenantId" \
        objectId="$objectId" \
        keyVaultSkuTier="$keyVaultSkuTier" \
        tagValues="$tagValues";
then
    echo "Deployment of Azure Key Vault failed, please see the error above."
    exit 1
else
    echo "Deployment of Azure Key Vault succeeded."
fi

echo "Deploying Azure Storage Account..."
if ! az deployment group create \
    --resource-group "$AZURE_RESOURCE_GROUP_NAME" \
    --template-file ./storageaccount/storageaccount.template.json \
    --parameters \
        storageAccountName="$storageAccountName" \
        storageAccountSku="$storageAccountSku" \
        storageAccountSkuTier="$storageAccountSkuTier" \
        storageAccountLocation="$storageAccountLocation" \
        encryptionEnabled="$encryptionEnabled";
then
    echo "Deployment of Azure Storage Account failed, please see the error above."
    exit 1
else
    echo "Deployment of Azure Storage Account succeeded."
fi

# Configure Key Vault access policy (Juan)

# Generate token for ADB (Juan)

# Store token in Key Vault (Juan)

# Store Storage Account keys in Key Vault (Juan)
