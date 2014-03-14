#!/bin/bash
#
# Initial data for Keystone using python-keystoneclient
#
# Tenant               User       Roles
# ------------------------------------------------------------------
# service              glance     admin
# service              heat       service        # if enabled
# Tempest Only:
# alt_demo             alt_demo  Member
#
# Variables set before calling this script:
# SERVICE_TOKEN - aka admin_token in keystone.conf
# SERVICE_ENDPOINT - local Keystone admin endpoint
# SERVICE_TENANT_NAME - name of tenant containing service accounts
# SERVICE_HOST - host used for endpoint creation
# ENABLED_SERVICES - stack.sh's list of services to start
# DEVSTACK_DIR - Top-level DevStack directory
# KEYSTONE_CATALOG_BACKEND - used to determine service catalog creation

# Defaults
# --------

ADMIN_PASSWORD=${ADMIN_PASSWORD:-secrete}
SERVICE_PASSWORD=${SERVICE_PASSWORD:-$ADMIN_PASSWORD}
export SERVICE_TOKEN=$SERVICE_TOKEN
export SERVICE_ENDPOINT=$SERVICE_ENDPOINT
SERVICE_TENANT_NAME=${SERVICE_TENANT_NAME:-service}

# Roles
# -----

# The ResellerAdmin role is used by Nova and Ceilometer so we need to keep it.
# The admin role in swift allows a user to act as an admin for their tenant,
# but ResellerAdmin is needed for a user to act as any tenant. The name of this
# role is also configurable in swift-proxy.conf
keystone role-create --name=ResellerAdmin
# Service role, so service users do not have to be admins
keystone role-create --name=service


# Services
# --------

if [[ "$ENABLED_SERVICES" =~ "n-api" ]] && [[ "$ENABLED_SERVICES" =~ "s-proxy" || "$ENABLED_SERVICES" =~ "swift" ]]; then
    # Nova needs ResellerAdmin role to download images when accessing
    # swift through the s3 api.
    keystone user-role-add \
        --tenant $SERVICE_TENANT_NAME \
        --user nova \
        --role ResellerAdmin
fi

# Heat
if [[ "$ENABLED_SERVICES" =~ "heat" ]]; then
    keystone user-create --name=heat \
        --pass="$SERVICE_PASSWORD" \
        --tenant $SERVICE_TENANT_NAME \
        --email=heat@example.com
    keystone user-role-add --tenant $SERVICE_TENANT_NAME \
        --user heat \
        --role service
    # heat_stack_user role is for users created by Heat
    keystone role-create --name heat_stack_user
    if [[ "$KEYSTONE_CATALOG_BACKEND" = 'sql' ]]; then
        keystone service-create \
            --name=heat-cfn \
            --type=cloudformation \
            --description="Heat CloudFormation Service"
        keystone endpoint-create \
            --region RegionOne \
            --service heat-cfn \
            --publicurl "http://$SERVICE_HOST:$HEAT_API_CFN_PORT/v1" \
            --adminurl "http://$SERVICE_HOST:$HEAT_API_CFN_PORT/v1" \
            --internalurl "http://$SERVICE_HOST:$HEAT_API_CFN_PORT/v1"
        keystone service-create \
            --name=heat \
            --type=orchestration \
            --description="Heat Service"
        keystone endpoint-create \
            --region RegionOne \
            --service heat \
            --publicurl "http://$SERVICE_HOST:$HEAT_API_PORT/v1/\$(tenant_id)s" \
            --adminurl "http://$SERVICE_HOST:$HEAT_API_PORT/v1/\$(tenant_id)s" \
            --internalurl "http://$SERVICE_HOST:$HEAT_API_PORT/v1/\$(tenant_id)s"
    fi
fi

# Glance
if [[ "$ENABLED_SERVICES" =~ "g-api" ]]; then
    keystone user-create \
        --name=glance \
        --pass="$SERVICE_PASSWORD" \
        --tenant $SERVICE_TENANT_NAME \
        --email=glance@example.com
    keystone user-role-add \
        --tenant $SERVICE_TENANT_NAME \
        --user glance \
        --role admin
    if [[ "$KEYSTONE_CATALOG_BACKEND" = 'sql' ]]; then
        keystone service-create \
            --name=glance \
            --type=image \
            --description="Glance Image Service"
        keystone endpoint-create \
            --region RegionOne \
            --service glance \
            --publicurl "http://$SERVICE_HOST:9292" \
            --adminurl "http://$SERVICE_HOST:9292" \
            --internalurl "http://$SERVICE_HOST:9292"
    fi
fi

# Ceilometer
if [[ "$ENABLED_SERVICES" =~ "ceilometer" ]] && [[ "$ENABLED_SERVICES" =~ "s-proxy" || "$ENABLED_SERVICES" =~ "swift" ]]; then
    # Ceilometer needs ResellerAdmin role to access swift account stats.
    keystone user-role-add --tenant $SERVICE_TENANT_NAME \
        --user ceilometer \
        --role ResellerAdmin
fi

# EC2
if [[ "$ENABLED_SERVICES" =~ "n-api" ]]; then
    if [[ "$KEYSTONE_CATALOG_BACKEND" = 'sql' ]]; then
        keystone service-create \
            --name=ec2 \
            --type=ec2 \
            --description="EC2 Compatibility Layer"
        keystone endpoint-create \
            --region RegionOne \
            --service ec2 \
            --publicurl "http://$SERVICE_HOST:8773/services/Cloud" \
            --adminurl "http://$SERVICE_HOST:8773/services/Admin" \
            --internalurl "http://$SERVICE_HOST:8773/services/Cloud"
    fi
fi

# S3
if [[ "$ENABLED_SERVICES" =~ "n-obj" || "$ENABLED_SERVICES" =~ "swift3" ]]; then
    if [[ "$KEYSTONE_CATALOG_BACKEND" = 'sql' ]]; then
        keystone service-create \
            --name=s3 \
            --type=s3 \
            --description="S3"
        keystone endpoint-create \
            --region RegionOne \
            --service s3 \
            --publicurl "http://$SERVICE_HOST:$S3_SERVICE_PORT" \
            --adminurl "http://$SERVICE_HOST:$S3_SERVICE_PORT" \
            --internalurl "http://$SERVICE_HOST:$S3_SERVICE_PORT"
    fi
fi

if [[ "$ENABLED_SERVICES" =~ "tempest" ]]; then
    # Tempest has some tests that validate various authorization checks
    # between two regular users in separate tenants
    keystone tenant-create \
        --name=alt_demo
    keystone user-create \
        --name=alt_demo \
        --pass="$ADMIN_PASSWORD" \
        --email=alt_demo@example.com
    keystone user-role-add \
        --tenant alt_demo \
        --user alt_demo \
        --role Member
fi

ORGA=$(get_id keystone tenant-create \
            --name=orga)
PROJECTAA=$(get_id keystone tenant-create \
            --name=projecta \
            --parent_project_id=$ORGA)
PROJECTAB=$(get_id keystone tenant-create \
            --name=projectb \
            --parent_project_id=$ORGA)
ORGB=$(get_id keystone tenant-create \
            --name=orgb)
PROJECTBA=$(get_id keystone tenant-create \
            --name=projecta \
            --parent_project_id=$ORGB)

USER=$(get_id keystone user-create \
            --name=orga \
            --pass="$ADMIN_PASSWORD" \
            --email=orga@example.com)

keystone user-role-add \
            --tenant-id $ORGA \
            --user-id $USER \
            --role-id $MEMBER_ROLE

USER=$(get_id keystone user-create \
            --name=orgb \
            --pass="$ADMIN_PASSWORD" \
            --email=orga@example.com)

keystone user-role-add \
            --tenant-id $ORGB \
            --user-id $USER \
            --role-id $MEMBER_ROLE

USER=$(get_id keystone user-create \
            --name=orga.projecta \
            --pass="$ADMIN_PASSWORD" \
            --email=orga@example.com)

keystone user-role-add \
            --tenant-id $PROJECTAA \
            --user-id $USER \
            --role-id $MEMBER_ROLE

USER=$(get_id keystone user-create \
            --name=orga.projectb \
            --pass="$ADMIN_PASSWORD" \
            --email=orga@example.com)

keystone user-role-add \
            --tenant-id $PROJECTAB \
            --user-id $USER \
            --role-id $MEMBER_ROLE

USER=$(get_id keystone user-create \
            --name=orgb.projecta \
            --pass="$ADMIN_PASSWORD" \
            --email=orga@example.com)

keystone user-role-add \
            --tenant-id $PROJECTBA \
            --user-id $USER \
            --role-id $MEMBER_ROLE
