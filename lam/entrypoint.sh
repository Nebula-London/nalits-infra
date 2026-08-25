#!/bin/bash
# ===========================================
# LAM Entrypoint - Auto-configuration script
# Runs on container startup to configure LAM
# ===========================================

set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Wait for Samba AD to be ready
log "Waiting for Samba AD LDAPS..."
for i in {1..30}; do
    if ldapsearch -x -H ldaps://samba:636 -b "DC=SAMBA,DC=INTERNAL" -s base dn -Z > /dev/null 2>&1; then
        log "Samba AD LDAPS is ready!"
        break
    fi
    log "Waiting for Samba AD... ($i/30)"
    sleep 5
done

# Generate LAM config from template
log "Generating LAM configuration..."
AD_DOMAIN="${AD_DOMAIN:-SAMBA.INTERNAL}"
AD_BASE_DN="DC=${AD_DOMAIN//./,DC=}"

cat > /var/lib/ldap-account-manager/config/lam.conf <<EOF
<?php
// ===========================================
// LAM Configuration for Samba AD
// Auto-generated on $(date)
// ===========================================

\$cfg->ServerURL = 'ldaps://samba:636';
\$cfg->ServerPort = 636;
\$cfg->ServerAD = true;
\$cfg->ServerTLS = true;
\$cfg->ServerTLSVerify = false;
\$cfg->ServerStartTLS = false;
\$cfg->ServerBaseDN = '${AD_BASE_DN}';
\$cfg->ServerLoginDN = 'CN=Administrator,CN=Users,${AD_BASE_DN}';
\$cfg->ServerLoginPass = getenv('SAMBA_ADMIN_PASSWORD') ?: 'ChangeMe_SambaAdmin_2024!';

\$cfg->ServerTitle = 'RentOption AD Management';
\$cfg->ServerDescription = 'Internal LDAP Account Manager for Samba AD';
\$cfg->Language = 'en_US';
\$cfg->TimeZone = 'UTC';

\$cfg->SessionTimeout = 3600;
\$cfg->AutoNumber = true;
\$cfg->AutoNumberStart = 10000;

\$cfg->PasswdMinLength = 8;
\$cfg->PasswdMaxLength = 128;
\$cfg->PasswdMinUpper = 1;
\$cfg->PasswdMinLower = 1;
\$cfg->PasswdMinDigit = 1;
\$cfg->PasswdMinSpecial = 1;

\$cfg->UserList = 'CN=Users,${AD_BASE_DN}';
\$cfg->GroupList = 'CN=Users,${AD_BASE_DN}';

\$cfg->UserAttrDisplay = 'cn';
\$cfg->UserAttrUID = 'cn';
\$cfg->UserAttrPassword = 'userPassword';
\$cfg->UserAttrMail = 'mail';
\$cfg->UserAttrPhone = 'telephoneNumber';
\$cfg->UserAttrMobile = 'mobile';
\$cfg->UserAttrFax = 'facsimileTelephoneNumber';
\$cfg->UserAttrStreet = 'streetAddress';
\$cfg->UserAttrCity = 'l';
\$cfg->UserAttrState = 'st';
\$cfg->UserAttrPostalCode = 'postalCode';
\$cfg->UserAttrCountry = 'co';
\$cfg->UserAttrDescription = 'description';
\$cfg->UserAttrEmployeeNumber = 'employeeNumber';
\$cfg->UserAttrEmployeeType = 'employeeType';
\$cfg->UserAttrTitle = 'title';
\$cfg->UserAttrDepartment = 'departmentNumber';
\$cfg->UserAttrCompany = 'o';
\$cfg->UserAttrManager = 'manager';
\$cfg->UserAttrSecretary = 'secretary';
\$cfg->UserAttrLastLogin = 'lastLogonTimestamp';
\$cfg->UserAttrLastChange = 'pwdLastSet';
\$cfg->UserAttrLockout = 'lockoutTime';
\$cfg->UserAttrBadPwdCount = 'badPwdCount';
\$cfg->UserAttrAccountExpires = 'accountExpires';
\$cfg->UserAttrLoginShell = 'loginShell';
\$cfg->UserAttrHomeDirectory = 'homeDirectory';
\$cfg->UserAttrHomeDrive = 'homeDrive';
\$cfg->UserAttrProfilePath = 'profilePath';
\$cfg->UserAttrScriptPath = 'scriptPath';

\$cfg->GroupAttrDisplay = 'cn';
\$cfg->GroupAttrName = 'cn';
\$cfg->GroupAttrDescription = 'description';
\$cfg->GroupAttrMember = 'member';

\$cfg->ServerAD = true;
\$cfg->UserRDNAttrib = 'cn';
\$cfg->UserObjectClass = array('user', 'person', 'organizationalPerson');
\$cfg->GroupObjectClass = array('group');
\$cfg->UserSearchFilter = '(&(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))';
\$cfg->GroupSearchFilter = '(objectClass=group)';

\$cfg->PasswordHash = 'SSHA';

\$cfg->TreeView = true;
\$cfg->TreeViewShowUsers = true;
\$cfg->TreeViewShowGroups = true;
\$cfg->TreeViewShowContainers = true;

\$cfg->ModuleUser = true;
\$cfg->ModuleGroup = true;
\$cfg->ModuleContainer = true;
\$cfg->ModulePolicies = true;
\$cfg->ModuleSchema = true;
\$cfg->ModuleTools = true;
\$cfg->ModuleExport = true;
\$cfg->ModuleImport = true;
\$cfg->ModuleReports = true;

\$cfg->UserCreate = true;
\$cfg->UserEdit = true;
\$cfg->UserDelete = true;
\$cfg->UserCopy = true;
\$cfg->UserMove = true;
\$cfg->GroupCreate = true;
\$cfg->GroupEdit = true;
\$cfg->GroupDelete = true;
\$cfg->GroupCopy = true;
\$cfg->GroupMove = true;

\$cfg->SelfService = true;
\$cfg->SelfServiceEdit = array('mail', 'telephoneNumber', 'mobile', 'description');
\$cfg->SelfServicePasswd = true;

\$cfg->LogLevel = 3;
\$cfg->LogFile = '/var/log/lam/lam.log';

\$cfg->CronJobs = array();
\$cfg->CustomFields = array();
\$cfg->HelpURL = 'https://www.ldap-account-manager.org/';
EOF

log "LAM configuration generated successfully!"

# Start Apache (LAM runs on Apache)
exec apache2-foreground