// [STEP E01] Import entities from all registers
LOAD CSV WITH HEADERS FROM
'https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/feature-model-revision/data/csv/indices.csv'
AS line FIELDTERMINATOR ','

WITH line
WHERE line.index IN [
    'Personenregister',
    'Ortsregister',
    'Sachbegriffe',
    'Himmelserscheinungen'
  ]
  AND trim(coalesce(line.sbw_id, '')) <> ''

MERGE (entity:Entity {
  uuid: trim(line.sbw_id)
})

SET entity += apoc.map.clean(
  {
    label: trim(line.label),
    forename: trim(line.forename),
    surname: trim(line.surname),
    description: trim(line.desc),
    birth: trim(line.birth),
    death: trim(line.death),
    floruitNotBefore: trim(line.floruit_notBefore),
    floruitNotAfter: trim(line.floruit_notAfter),
    floruit: trim(line.floruit)
  },
  [],
  ['', null]
)

SET entity.registers = apoc.coll.toSet(
  coalesce(entity.registers, []) + line.index
)

FOREACH (_ IN CASE
  WHEN line.index = 'Personenregister'
  THEN [1]
  ELSE []
END |
  SET entity:Person
)

FOREACH (_ IN CASE
  WHEN line.index = 'Ortsregister'
  THEN [1]
  ELSE []
END |
  SET entity:Place
)

FOREACH (_ IN CASE
  WHEN line.index IN [
    'Sachbegriffe',
    'Himmelserscheinungen'
  ]
  THEN [1]
  ELSE []
END |
  SET entity:Term
)

RETURN
  line.index AS register,
  count(DISTINCT entity) AS importedEntities
ORDER BY register;


// [STEP E02] Refine Bible verses
MATCH (verse:Entity:Term)
WHERE verse.label STARTS WITH 'Bibel, AT, '
   OR verse.label STARTS WITH 'Bibel, NT, '
   OR verse.label STARTS WITH 'Bibel, Apocr., '

SET verse:BibleVerse
REMOVE verse:Term

RETURN count(verse) AS importedBibleVerses;


// [STEP E03] Create Bible hierarchy
UNWIND [
  {
    uuid: 'ed_2328ba44-f869-4539-85b0-331bf71bb8ca',
    label: 'Bibel, Altes Testament',
    prefix: 'Bibel, AT, '
  },
  {
    uuid: 'ed_e19cdb1f-a3a4-400a-8234-7490ddfa568d',
    label: 'Bibel, Neues Testament',
    prefix: 'Bibel, NT, '
  },
  {
    uuid: 'ed_13f93f59-da64-4c6e-a712-7c880958ac4a',
    label: 'Bibel, Apokryphen',
    prefix: 'Bibel, Apocr., '
  }
] AS config

MATCH (bible:Entity:Term {
  uuid: 'ed_l24_sb1_lfb'
})

MERGE (part:Entity:Term {
  uuid: config.uuid
})

SET part.label = config.label

CREATE (partAnnotation:Annotation {
  uuid: randomUUID(),
  type: 'subOf'
})

CREATE (part)-[:HAS_ANNOTATION]->(partAnnotation)
CREATE (partAnnotation)-[:REFERS_TO]->(bible)

WITH
  config,
  part

MATCH (verse:Entity:BibleVerse)
WHERE verse.label STARTS WITH config.prefix

SET verse.label = trim(
  substring(
    verse.label,
    size(config.prefix)
  )
)

CREATE (verseAnnotation:Annotation {
  uuid: randomUUID(),
  type: 'subOf'
})

CREATE (verse)-[:HAS_ANNOTATION]->(verseAnnotation)
CREATE (verseAnnotation)-[:REFERS_TO]->(part)

RETURN
  part.label AS biblePart,
  count(verse) AS importedVerses
ORDER BY biblePart;


// [STEP E04] Create astronomical hierarchy
MERGE (phenomenonGroup:Entity:Term {
  uuid: 'ed_2eca2056-869f-4c8d-9c48-7e28fecef062'
})

SET phenomenonGroup.label = 'Himmelserscheinung'

WITH phenomenonGroup

MATCH (phenomenon:Entity:Term)
WHERE 'Himmelserscheinungen' IN coalesce(
  phenomenon.registers,
  []
)
  AND phenomenon <> phenomenonGroup

CREATE (annotation:Annotation {
  uuid: randomUUID(),
  type: 'subOf'
})

CREATE (phenomenon)-[:HAS_ANNOTATION]->(annotation)
CREATE (annotation)-[:REFERS_TO]->(phenomenonGroup)

RETURN count(phenomenon) AS importedAstronomicalPhenomena;


// [STEP E05] Remove temporary register information
MATCH (entity:Entity)
WHERE entity.registers IS NOT NULL

REMOVE entity.registers

RETURN count(entity) AS cleanedEntities;


// [STEP E06] Move descriptions to Annotation and Text nodes
MATCH (entity:Entity)
WHERE trim(
  coalesce(
    toString(entity.description),
    ''
  )
) <> ''

WITH
  entity,
  trim(toString(entity.description)) AS description

CREATE (textNode:Text:Content {
  uuid: randomUUID(),
  text: description
})

CREATE (annotation:Annotation {
  uuid: randomUUID(),
  type: 'description'
})

CREATE (entity)-[:HAS_ANNOTATION]->(annotation)
CREATE (annotation)-[:REFERS_TO]->(textNode)

REMOVE entity.description

RETURN count(entity) AS importedEntityDescriptions;


// [STEP E07] Import alternative labels
LOAD CSV WITH HEADERS FROM
'https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/feature-model-revision/data/csv/indices.csv'
AS line FIELDTERMINATOR ','

WITH line
WHERE line.index = 'altName'
  AND trim(coalesce(line.sbw_id, '')) <> ''
  AND any(value IN [
    line.label,
    line.forename,
    line.surname
  ] WHERE trim(coalesce(value, '')) <> '')

MATCH (entity:Entity {
  uuid: trim(line.sbw_id)
})

CREATE (annotation:Annotation {
  uuid: randomUUID()
})

SET annotation += apoc.map.clean(
  {
    type: 'altLabel',
    label: trim(line.label),
    forename: trim(line.forename),
    surname: trim(line.surname)
  },
  [],
  ['', null]
)

CREATE (entity)-[:HAS_ANNOTATION]->(annotation)

RETURN count(annotation) AS importedAlternativeLabels;


// [STEP E08] Import normalized authority references
LOAD CSV WITH HEADERS FROM
'https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/feature-model-revision/data/csv/indices.csv'
AS line FIELDTERMINATOR ','

WITH line
WHERE line.index = 'normdata'
  AND trim(coalesce(line.sbw_id, '')) <> ''
  AND trim(coalesce(line.URL, '')) <> ''

MATCH (entity:Entity {
  uuid: trim(line.sbw_id)
})

WITH
  entity,
  trim(line.URL) AS url

WITH
  entity,
  url,
  replace(split(url, '/')[2], 'www.', '') AS host,
  [
    part IN split(url, '/')
    WHERE part <> ''
      AND NOT part STARTS WITH 'http'
  ] AS parts

WITH
  entity,
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

    WHEN host CONTAINS 'emlo.bodleian.ox.ac.uk'
    THEN 'emlo'

    WHEN host CONTAINS 'simbad.u-strasbg.fr'
    THEN 'simbad'

    WHEN host CONTAINS 'ssd.jpl.nasa.gov'
    THEN 'sbdb'

    ELSE host
  END AS namespace

WITH
  entity,
  url,
  namespace,
  parts,
  CASE
    WHEN namespace IN [
      'wikidata',
      'gnd',
      'emlo'
    ]
    THEN last(parts)

    WHEN namespace = 'geonames'
    THEN parts[1]

    WHEN namespace = 'simbad'
      AND url CONTAINS 'Ident='
    THEN split(url, 'Ident=')[1]

    WHEN namespace = 'sbdb'
      AND url CONTAINS 'sstr='
    THEN split(url, 'sstr=')[1]

    ELSE last(parts)
  END AS rawIdentifier

WITH
  entity,
  url,
  namespace,
  trim(
    head(
      split(
        head(split(rawIdentifier, '&')),
        '#'
      )
    )
  ) AS identifier

WHERE identifier <> ''

CREATE (annotation:Annotation {
  uuid: randomUUID(),
  type: 'normdata',
  namespace: namespace,
  identifier: identifier,
  url: url
})

CREATE (entity)-[:HAS_ANNOTATION]->(annotation)

RETURN count(annotation) AS importedNormdataAnnotations;


// [STEP E09] Import entity cross-references
LOAD CSV WITH HEADERS FROM
'https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/feature-model-revision/data/csv/relations.csv'
AS line FIELDTERMINATOR ','

WITH line
WHERE line.type = 'cross_reference'
  AND trim(coalesce(line.source, '')) <> ''
  AND trim(coalesce(line.target, '')) <> ''

MATCH (source:Entity {
  uuid: trim(line.source)
})

MATCH (target:Entity {
  uuid: trim(line.target)
})

CREATE (annotation:Annotation {
  uuid: randomUUID(),
  type: 'seeAlso'
})

CREATE (source)-[:HAS_ANNOTATION]->(annotation)
CREATE (annotation)-[:REFERS_TO]->(target)

RETURN count(annotation) AS importedCrossReferences;
