/*
 * Sonatype Nexus (TM) Open Source Version
 * Copyright (c) 2008-present Sonatype, Inc.
 * All rights reserved. Includes the third-party code listed at http://links.sonatype.com/products/nexus/oss/attributions.
 *
 * This program and the accompanying materials are made available under the terms of the Eclipse Public License Version 1.0,
 * which accompanies this distribution and is available at http://www.eclipse.org/legal/epl-v10.html.
 *
 * Sonatype Nexus (TM) Professional Version is available from Sonatype, Inc. "Sonatype" and "Sonatype Nexus" are trademarks
 * of Sonatype, Inc. Apache Maven is a trademark of the Apache Software Foundation. M2eclipse is a trademark of the
 * Eclipse Foundation. All other trademarks are the property of their respective owners.
*/

/*
 * Utility script that scans blobstores and reads the asset properties files within to summarize which repositories
 * are using the blob store, and how much space each is consuming and how much space could potentially be reclaimed by
 * running a compact blobstore task.
 *
 * The script retrieves the blobstore locations from the Nexus system and also all defined repositories.
 *
 * It is possible to specify a whitelist of repository names *OR* a blacklist (whitelist takes priority)
 * If a whitelist is provided, only those repositories whitelisted will be included.
 * If a blacklist is provided (and no whitelist), any repositories that are blacklisted will be omitted.
 *
 * Any empty repositories are also included.
 *
 * The script tabulates both the total size, and the size that could be reclaimed by performing a compact blob store
 * task.
 *
 * Script was developed to run as an 'Execute Script' task within Nexus Repository Manager.
 *

 * ---------------- BEGIN CONFIGURABLE SECTION -------------*

 * Whitelist - a list of repository names that should be the only items included.
 *
 *   For example: REPOSITORY_WHITELIST = ['maven-central', 'npm-hosted']
 */

REPOSITORY_WHITELIST = []

/* Blacklist - a list of repository names that should not be included.
 *   This will only apply if REPOSITORY_WHITELIST is not set
 *
 *   For example: REPOSITORY_BLACKLIST = ['maven-central', 'npm-hosted']
 */

REPOSITORY_BLACKLIST = []

/* ---------------- END CONFIGURABLE SECTION ---------------*/

import groovy.json.JsonOutput

import java.text.SimpleDateFormat
import org.sonatype.nexus.common.app.ApplicationDirectories
import org.sonatype.nexus.internal.app.ApplicationDirectoriesImpl
import org.slf4j.LoggerFactory


def log = LoggerFactory.getLogger(this.class)

ApplicationDirectories applicationDirectories =
    (ApplicationDirectories)container.lookup(ApplicationDirectoriesImpl.class.name)

List<File> blobStoreDirectories = []
hasWhitelist = REPOSITORY_WHITELIST.size() > 0
hasBlacklist = !hasWhitelist && REPOSITORY_BLACKLIST.size() > 0

//Default location of results is the Nexus temporary directory
File resultsFileLocation = applicationDirectories.getTemporaryDirectory()

Map<String, BlobStatistics> blobStatCollection = [:].withDefault { 0 }

class BlobStatistics
{
  int totalRepoNameMissingCount = 0
  long totalBlobStoreBytes = 0
  long totalReclaimableBytes = 0
  Map<String, RepoStatistics> repositories = [:]
}

class RepoStatistics {
  long totalBytes = 0
  long reclaimableBytes = 0
}

def collectMetrics(final BlobStatistics blobstat, Set<String> unmapped,
                   final Properties properties, final File propertiesFile) {
  def repo = properties.'@Bucket.repo-name'
  if(repo == null && properties.'@BlobStore.direct-path') {
    repo = 'SYSTEM:direct-path'
  }
  if(repo == null) {
    // unexpected - log the unexpected condition
    if(blobstat.totalRepoNameMissingCount <= 50){
      log.warn('Repository name missing from {} : {}', propertiesFile.absolutePath, properties)
      log.info('full details: {}', properties)
    }
    blobstat.totalRepoNameMissingCount++
  } else {
    if (!blobstat.repositories.containsKey(repo)) {
      if (!unmapped.contains(repo)) {
        if (!repo.equals('SYSTEM:direct-path')) {
          log.info('Found unknown repository in {}: {}', propertiesFile.absolutePath, repo)
        }
        blobstat.repositories.put(repo as String, new RepoStatistics())
      }
    }

    if (blobstat.repositories.containsKey(repo)) {
      blobstat.repositories."$repo".totalBytes += (properties.size as long)
      if (!repo.equals('SYSTEM:direct-path')) {
        blobstat.totalBlobStoreBytes += (properties.size as long)
      }

      if (properties.'deleted') {
        blobstat.repositories."$repo".reclaimableBytes += (properties.size as long)
        if (!repo.equals('SYSTEM:direct-path')) {
          blobstat.totalReclaimableBytes += (properties.size as long)
        }
      }
    }
  }
}

def passesWhiteBlackList(final String name) {
  if (hasWhitelist) {
    return REPOSITORY_WHITELIST.contains(name)
  }
  if (hasBlacklist) {
    return !REPOSITORY_BLACKLIST.contains(name)
  }
  return true
}

def getScanner(final File baseDirectory) {
  def ant = new AntBuilder()
  def scanner = ant.fileScanner {
    fileset(dir: baseDirectory) {
      include(name: '**/*.properties')
      exclude(name: '**/metadata.properties')
      exclude(name: '**/*metrics.properties')
      exclude(name: '**/tmp')
    }
  }
  return scanner
}

Map<String, Map<String, Boolean>> storeRepositoryLookup = [:].withDefault { [:] }

repository.getRepositoryManager().browse().each { repo ->
  def blobStoreName = repo.properties.configuration.attributes.storage.blobStoreName
  storeRepositoryLookup.get(blobStoreName).put(repo.name, passesWhiteBlackList(repo.name))
}

blobStore.getBlobStoreManager().browse().each { blobstore ->
  if (blobstore.getProperties().get('groupable')) {
    if (blobstore.getProperties().get("blobStoreConfiguration").type == "S3") {
      log.info("Ignoring blobstore {} as it is using S3", blobstore.getProperties().get("blobStoreConfiguration").name);
    }
    else {
      try {
        blobStoreDirectories.add(blobstore.getProperties().get("absoluteBlobDir").toFile())
      } catch (Exception ex) {
        log.warn('Unable to add blobstore {} of type {}: {}', blobstore.getProperties().get("blobStoreConfiguration").name, blobstore.getProperties().get("blobStoreConfiguration").type, ex.getMessage())
        log.info('details: {}', blobstore.getProperties())
      }
    }
  }
}

log.info('Blob Storage scan STARTED.')
blobStoreDirectories.each { blobStore ->

  log.info('Scanning {}', blobStore.absolutePath)

  BlobStatistics blobStat = new BlobStatistics()

  Set<String> unmapped = new HashSet<>()
  storeRepositoryLookup[blobStore.getName()].each { key, value ->
    if (value) {
      blobStat.repositories.put(key, new RepoStatistics())
    } else {
      unmapped.add(key)
    }
  }

  getScanner(blobStore).each { File propertiesFile ->
    def properties = new Properties()
    propertiesFile.withInputStream { is ->
      properties.load(is)
    }
    collectMetrics(blobStat, unmapped, properties, propertiesFile)
  }
  blobStatCollection.put(blobStore.getName(), blobStat)
}

blobStatCollection.each() { blobStoreName, blobStat ->
  RepoStatistics directPath = blobStat.repositories.remove('SYSTEM:direct-path')
  if (directPath!=null) {
    log.info("Direct-Path size in blobstore {}: {} - reclaimable: {}", blobStoreName, directPath.totalBytes, directPath.reclaimableBytes)
  }
}

def filename = "repoSizes-${new SimpleDateFormat("yyyyMMdd-HHmmss").format(new Date())}.json"
File resultsFile = new File(resultsFileLocation, filename)
resultsFile.withWriter { Writer writer ->
  writer << JsonOutput.prettyPrint(JsonOutput
      .toJson(blobStatCollection
      .findAll {a, b -> b.repositories.size() > 0}
      .toSorted {a, b -> b.value.totalBlobStoreBytes <=> a.value.totalBlobStoreBytes}))
}
log.info('Blob Storage scan ENDED. Report at {}', resultsFile.absolutePath)