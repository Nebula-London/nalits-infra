# SSH certificate authority

Normal SSH access is: SSO authentication -> authorization policy -> short-lived OpenSSH certificate -> WireGuard -> private VM. Permanent engineer keys are not distributed across the fleet. The CA private key stays in the security boundary and is rotated/recovered through the documented break-glass procedure.
