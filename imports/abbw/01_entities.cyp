// [STEP E01] Import entities with base and refinement labels
CALL apoc.load.json(
  'https://abbw.adwmainz.net/exist/rest/db/json/data/indices.json'
)
YIELD value AS json

UNWIND json.indexes AS index
UNWIND index.entities AS entityGroup
UNWIND entityGroup.entity AS sourceEntity

CALL apoc.create.node(
  [entityGroup.label, 'Entity'],
  sourceEntity.properties
)
YIELD node

RETURN count(node) AS importedEntities;


// [STEP E02] Move entity descriptions to Annotation and Text nodes
MATCH (entity:Entity)
WHERE entity.description IS NOT NULL
  AND trim(toString(entity.description)) <> ''

WITH
  entity,
  trim(toString(entity.description)) AS description

CREATE (annotation:Annotation {
  uuid: randomUUID(),
  type: 'description'
})

CREATE (textNode:Text:Content {
  uuid: randomUUID(),
  text: description
})

CREATE (entity)-[:HAS_ANNOTATION]->(annotation)
CREATE (annotation)-[:REFERS_TO]->(textNode)

REMOVE entity.description

RETURN count(entity) AS importedEntityDescriptions;


// [STEP E03] Import additional labels as annotations
CALL apoc.load.json(
  'https://abbw.adwmainz.net/exist/rest/db/json/data/indices.json'
)
YIELD value AS json

UNWIND json.indexes AS index
UNWIND index.addLabels AS addLabelGroup
UNWIND addLabelGroup.addLabel AS sourceAnnotation

MATCH (entity:Entity {
  uuid: sourceAnnotation.target_uuid
})

WITH
  entity,
  sourceAnnotation,
  apoc.convert.toMap(sourceAnnotation.properties) AS properties,
  coalesce(
    sourceAnnotation.uuid,
    sourceAnnotation.properties.uuid,
    randomUUID()
  ) AS annotationUuid

MERGE (annotation:Annotation {
  uuid: annotationUuid
})

SET annotation += apoc.map.removeKeys(
  properties,
  ['uuid']
)

MERGE (entity)-[:HAS_ANNOTATION]->(annotation)

RETURN count(DISTINCT annotation) AS importedAddLabelAnnotations;


// [STEP E04] Import authority references as normalized annotations
CALL apoc.load.json(
  'https://abbw.adwmainz.net/exist/rest/db/json/data/indices.json'
)
YIELD value AS json

UNWIND json.indexes AS index
UNWIND index.normdata.normlink AS normlink

WITH
  normlink,
  apoc.convert.toMap(normlink.properties) AS properties

WHERE normlink.target_uuid IS NOT NULL
  AND properties.url IS NOT NULL
  AND trim(toString(properties.url)) <> ''

MATCH (entity:Entity {
  uuid: normlink.target_uuid
})

WITH
  entity,
  normlink,
  properties,
  trim(toString(properties.url)) AS url

WITH
  entity,
  normlink,
  properties,
  url,
  replace(split(url, '/')[2], 'www.', '') AS host,
  [
    part IN split(url, '/')
    WHERE part <> ''
      AND NOT part STARTS WITH 'http'
  ] AS parts

WITH
  entity,
  normlink,
  properties,
  url,
  parts,
  CASE
    WHEN host CONTAINS 'wikidata.org'
    THEN 'wikidata'

    WHEN host = 'd-nb.info'
      AND 'gnd' IN parts
    THEN 'gnd'

    WHEN host CONTAINS 'geonames.org'
    THEN 'geonames'

    ELSE host
  END AS namespace

WITH
  entity,
  normlink,
  properties,
  url,
  namespace,
  parts,
  CASE
    WHEN namespace IN ['wikidata', 'gnd']
    THEN last(parts)

    WHEN namespace = 'geonames'
    THEN parts[1]

    ELSE last(parts)
  END AS identifier

WHERE identifier IS NOT NULL
  AND trim(toString(identifier)) <> ''

WITH
  entity,
  properties,
  url,
  namespace,
  trim(toString(identifier)) AS identifier,
  coalesce(
    normlink.uuid,
    properties.uuid,
    randomUUID()
  ) AS annotationUuid

MERGE (annotation:Annotation {
  uuid: annotationUuid
})

SET annotation += {
  type: 'normdata',
  identifier: identifier,
  namespace: namespace,
  url: url
}

MERGE (entity)-[:HAS_ANNOTATION]->(annotation)

RETURN count(DISTINCT annotation) AS importedNormdataAnnotations;


// [STEP E05] Import cross-references as seeAlso annotations
CALL apoc.load.json(
  'https://abbw.adwmainz.net/exist/rest/db/json/data/indices.json'
)
YIELD value AS json

UNWIND json.indexes AS index
UNWIND index.relations AS relationGroup
UNWIND relationGroup.relation AS relation

MATCH (source:Entity {
  uuid: relation.source
})

MATCH (target:Entity {
  uuid: relation.target
})

WITH
  source,
  target,
  coalesce(
    relation.uuid,
    relation.properties.uuid,
    randomUUID()
  ) AS annotationUuid

MERGE (annotation:Annotation {
  uuid: annotationUuid
})

SET annotation.type = 'seeAlso'

MERGE (source)-[:HAS_ANNOTATION]->(annotation)
MERGE (annotation)-[:REFERS_TO]->(target)

RETURN count(DISTINCT annotation) AS importedRelationAnnotations;


// [STEP E06] Import manually curated entity relations
LOAD CSV WITH HEADERS FROM
'https://docs.google.com/spreadsheets/d/e/2PACX-1vQPngiwCLRgfZ95o8vbNT-zGWtSY_ZnGb-_xT13fTMJwrGiRYSIY7kjDGayielh4MF_zwaTpGIuJBo8/pub?gid=157599467&single=true&output=csv'
AS line FIELDTERMINATOR ','

WITH line
WHERE line.source IS NOT NULL
  AND trim(line.source) <> ''
  AND line.target IS NOT NULL
  AND trim(line.target) <> ''
  AND line.Beziehung IS NOT NULL
  AND trim(line.Beziehung) <> ''

MATCH (source:Entity {
  uuid: trim(line.source)
})

MATCH (target:Entity {
  uuid: trim(line.target)
})

CREATE (annotation:Annotation {
  uuid: CASE
    WHEN line.uuid IS NOT NULL
      AND trim(line.uuid) <> ''
    THEN trim(line.uuid)

    ELSE randomUUID()
  END,
  type: 'relation',
  kind: trim(line.Beziehung),
  note: line.note
})

CREATE (source)-[:HAS_ANNOTATION]->(annotation)
CREATE (annotation)-[:REFERS_TO]->(target)

RETURN count(annotation) AS importedRelationAnnotations;
