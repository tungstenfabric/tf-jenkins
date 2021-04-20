
import org.sonatype.nexus.security.Roles
import org.sonatype.nexus.security.role.NoSuchRoleException
import org.sonatype.nexus.security.anonymous.AnonymousConfiguration
import org.sonatype.nexus.security.user.UserManager
import org.sonatype.nexus.security.realm.RealmManager

// List of privileges for pushing into all ci docker registries
def tf_docker_priv = ['nx-repository-admin-docker-tungsten_ci-*',
                      'nx-repository-view-docker-tungsten_ci-*',
                      'nx-repository-admin-docker-tungsten_gate_cache-*',
                      'nx-repository-view-docker-tungsten_gate_cache-*']

// Create or update tf docker role
String tf_docker_role_id = 'tf-ci-docker'
String tf_docker_role_name = tf_docker_role_id
String tf_docker_role_desc = 'Role allowing pushing into TF CI docker registries'
def existingRole = null
authManager = security.getSecuritySystem().getAuthorizationManager(UserManager.DEFAULT_SOURCE)
try {
    existingRole = authManager.getRole(tf_docker_role_id)
} catch (NoSuchRoleException ignored) {
    // could not find role
}
if (existingRole != null) {
    log.info("Update tf docker role")
    existingRole.setName(tf_docker_role_name)
    existingRole.setDescription(tf_docker_role_desc)
    existingRole.setPrivileges(tf_docker_priv as Set)
    existingRole.setRoles([] as Set)
    authManager.updateRole(existingRole)
} else {
    log.info("Create tf docker role")
    security.addRole(
        tf_docker_role_id,
        tf_docker_role_name,
        tf_docker_role_desc,
        tf_docker_priv,
        []
    )
}

// Update anonimous user roles
log.info("Add tf docker role into the user anonimous")
def tf_anonimous_roles = [Roles.ANONYMOUS_ROLE_ID, tf_docker_role_id]
security.setUserRoles(AnonymousConfiguration.DEFAULT_USER_ID, tf_anonimous_roles)

// Enable anonimous access to the system
log.info("Enable anonimous access to the system")
security.setAnonymousAccess(true)

// Enable docker realm
log.info("Enable docker realm done")
def realmManager = container.lookup(RealmManager.class.getName())
realmManager.enableRealm('DockerToken')
