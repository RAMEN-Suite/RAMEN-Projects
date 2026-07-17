// [STEP L01] Import letters
CALL apoc.load.json(
  'https://abbw.adwmainz.net/exist/rest/db/json/data/letters.json'
)
YIELD value AS json

UNWIND json.record AS record
WITH record
WHERE record.metadata.generalMetadataIsPresent = true

WITH
  record.metadata.generalMetadata AS gm,
  record.metadata.communication AS communication

WITH
  gm.attributes.uuid AS uuid,
  apoc.map.merge(
    apoc.convert.toMap(gm.attributes),
    {xmlDownload: communication.attributes.xmlDownload}
  ) AS props

MERGE (letter:Letter:Collection {uuid: uuid})
ON CREATE SET letter += props
ON MATCH SET letter += props
RETURN count(letter) AS importedOrMatchedLetters;


// [STEP L02] Split numeric prefixes from letter labels
MATCH (letter:Letter:Collection)
WHERE letter.label IS NOT NULL
  AND letter.label =~ '^[0-9]+.*'

WITH
  letter,
  apoc.text.regexGroups(letter.label, '^([0-9]+)(.*)$') AS groups

SET letter.number = groups[0][1],
    letter.label = trim(groups[0][2])

RETURN count(letter) AS normalizedLetterLabels;


// [STEP L03] Import correspondence actions as annotations
CALL apoc.load.json(
  'https://abbw.adwmainz.net/exist/rest/db/json/data/letters.json'
)
YIELD value AS json

UNWIND json.record AS record
WITH record
WHERE record.metadata.generalMetadataIsPresent = true

MATCH (letter:Letter:Collection {
  uuid: record.metadata.generalMetadata.attributes.uuid
})

UNWIND apoc.convert.toList(record.metadata.generalMetadata.correspDesc.correspAction) AS action

WITH
  letter,
  action,
  apoc.convert.toMap(action.attributes) AS actionProperties

MERGE (annot:Annotation {
  uuid: coalesce(
    action.uuid,
    actionProperties.uuid,
    randomUUID()
  )
})

SET annot += apoc.map.removeKeys(
  actionProperties,
  ['uuid']
)

MERGE (letter)-[:HAS_ANNOTATION]->(annot)
WITH annot, action

UNWIND CASE
  WHEN action.outgoingRelations IS NULL
    OR action.outgoingRelations.relation IS NULL
  THEN []
  ELSE apoc.convert.toList(action.outgoingRelations.relation)
END AS relation

MATCH (target:Entity {uuid: relation.uuid})

CALL apoc.create.relationship(annot, relation.relationType, {}, target)
YIELD rel

RETURN
  count(DISTINCT annot) AS importedCorrespAnnotations,
  count(rel) AS importedCorrespRelations;


// [STEP L04] Import witnesses and main letter texts
CALL apoc.load.json(
  'https://abbw.adwmainz.net/exist/rest/db/json/data/letters.json'
)
YIELD value AS json

UNWIND json.record AS record
WITH record
WHERE record.metadata.generalMetadataIsPresent = true

MATCH (letter:Letter:Collection {
  uuid: record.metadata.generalMetadata.attributes.uuid
})

WITH
  letter,
  record.metadata.variantMetadata.attributes AS vm,
  record.texts.variant.main_text AS mainText

WHERE mainText IS NOT NULL
  AND vm.uuid IS NOT NULL
  AND trim(toString(vm.uuid)) <> ''

MERGE (witness:Witness:Collection {
  uuid: vm.uuid
})

SET witness += apoc.convert.toMap(vm)
MERGE (witness)-[:PART_OF]->(letter)

MERGE (textNode:Text:Content)-[:PART_OF]->(witness)
ON CREATE SET textNode.uuid = coalesce(
  mainText.uuid,
  randomUUID()
)

SET textNode.text = mainText.text

RETURN
  count(DISTINCT witness) AS importedWitnesses,
  count(DISTINCT textNode) AS importedLetterTexts;


// [STEP L05] Import main letter text annotations
CALL apoc.load.json(
  'https://abbw.adwmainz.net/exist/rest/db/json/data/letters.json'
)
YIELD value AS json

UNWIND json.record AS record
WITH record
WHERE record.metadata.generalMetadataIsPresent = true

MATCH (letter:Letter:Collection {
  uuid: record.metadata.generalMetadata.attributes.uuid
})

MATCH (:Witness:Collection {
  uuid: record.metadata.variantMetadata.attributes.uuid
})<-[:PART_OF]-(textNode:Text:Content)

WITH textNode, record.texts.variant.main_text AS mainText
WHERE mainText IS NOT NULL

UNWIND CASE
  WHEN mainText.properties IS NULL THEN []
  ELSE apoc.convert.toList(mainText.properties)
END AS property

MERGE (annot:Annotation {
  uuid: coalesce(
    property.uuid,
    randomUUID()
  )
})

SET annot += apoc.map.removeKeys(
  apoc.convert.toMap(property),
  ['attributes', 'uuid', 'guid']
)

SET annot += CASE
  WHEN property.attributes IS NULL THEN {}
  ELSE apoc.convert.toMap(property.attributes)
END

SET annot.startIndex = CASE
      WHEN property.startIndex IS NULL THEN null
      ELSE toInteger(property.startIndex)
    END,
    annot.endIndex = CASE
      WHEN property.endIndex IS NULL THEN null
      ELSE toInteger(property.endIndex)
    END

SET annot.sameAs =
  CASE
    WHEN annot.sameAs IS NULL THEN null
    ELSE [x IN split(trim(toString(annot.sameAs)), ' ') WHERE trim(x) <> '']
  END

MERGE (textNode)-[:HAS_ANNOTATION]->(annot)
RETURN count(annot) AS importedLetterTextAnnotations;


// [STEP L06] Import abstract collections and texts
CALL apoc.load.json(
  'https://abbw.adwmainz.net/exist/rest/db/json/data/letters.json'
)
YIELD value AS json

UNWIND json.record AS record
WITH record
WHERE record.metadata.generalMetadataIsPresent = true

MATCH (letter:Letter:Collection {
  uuid: record.metadata.generalMetadata.attributes.uuid
})

WITH letter, record.texts.abstract AS abstract
WHERE abstract IS NOT NULL
  AND abstract.text IS NOT NULL

MERGE (abstractCollection:Abstract:Collection)-[:PART_OF]->(letter)
ON CREATE SET
  abstractCollection.uuid = coalesce(
    abstract.uuid,
    randomUUID()
  ),
  abstractCollection.label = 'Abstract zu ' + coalesce(
    letter.label,
    letter.uuid
  )

MERGE (textNode:Text:Content)-[:PART_OF]->(abstractCollection)
ON CREATE SET textNode.uuid = coalesce(
  abstract.textUuid,
  randomUUID()
)

SET textNode.text = abstract.text

RETURN
  count(abstractCollection) AS importedAbstractCollections,
  count(textNode) AS importedAbstractTexts;


// [STEP L07] Import abstract text annotations
CALL apoc.load.json(
  'https://abbw.adwmainz.net/exist/rest/db/json/data/letters.json'
)
YIELD value AS json

UNWIND json.record AS record
WITH record
WHERE record.metadata.generalMetadataIsPresent = true

MATCH (letter:Letter:Collection {
  uuid: record.metadata.generalMetadata.attributes.uuid
})

MATCH (abstractCollection:Abstract:Collection)-[:PART_OF]->(letter)
MATCH (textNode:Text:Content)-[:PART_OF]->(abstractCollection)

WITH textNode, record.texts.abstract AS abstract
WHERE abstract IS NOT NULL
  AND abstract.text IS NOT NULL

UNWIND CASE
  WHEN abstract.properties IS NULL THEN []
  ELSE apoc.convert.toList(abstract.properties)
END AS property

MERGE (annot:Annotation {
  uuid: coalesce(
    property.uuid,
    randomUUID()
  )
})

SET annot += apoc.map.removeKeys(
  apoc.convert.toMap(property),
  ['attributes', 'uuid', 'guid']
)

SET annot += CASE
  WHEN property.attributes IS NULL THEN {}
  ELSE apoc.convert.toMap(property.attributes)
END

SET annot.startIndex = CASE
      WHEN property.startIndex IS NULL THEN null
      ELSE toInteger(property.startIndex)
    END,
    annot.endIndex = CASE
      WHEN property.endIndex IS NULL THEN null
      ELSE toInteger(property.endIndex)
    END

SET annot.sameAs =
  CASE
    WHEN annot.sameAs IS NULL THEN null
    ELSE [x IN split(trim(toString(annot.sameAs)), ' ') WHERE trim(x) <> '']
  END

MERGE (textNode)-[:HAS_ANNOTATION]->(annot)
RETURN count(annot) AS importedAbstractAnnotations;


// [STEP L08] Import editorial comments as standalone texts
CALL apoc.load.json(
  'https://abbw.adwmainz.net/exist/rest/db/json/data/letters.json'
)
YIELD value AS json

UNWIND json.record AS record
WITH record
WHERE record.metadata.generalMetadataIsPresent = true

UNWIND CASE
  WHEN record.texts.variant.editorial_comments IS NULL THEN []
  ELSE apoc.convert.toList(record.texts.variant.editorial_comments)
END AS comment

MERGE (commentText:Text:Content {
  uuid: coalesce(comment.uuid, randomUUID())
})

SET commentText.text = comment.text
RETURN count(commentText) AS importedCommentTexts;


// [STEP L09] Import editorial comment annotations
CALL apoc.load.json(
  'https://abbw.adwmainz.net/exist/rest/db/json/data/letters.json'
)
YIELD value AS json

UNWIND json.record AS record
WITH record
WHERE record.metadata.generalMetadataIsPresent = true

UNWIND CASE
  WHEN record.texts.variant.editorial_comments IS NULL THEN []
  ELSE apoc.convert.toList(record.texts.variant.editorial_comments)
END AS comment

MATCH (commentText:Text:Content {
  uuid: comment.uuid
})

UNWIND CASE
  WHEN comment.properties IS NULL THEN []
  ELSE apoc.convert.toList(comment.properties)
END AS property

MERGE (annot:Annotation {
  uuid: coalesce(
    property.uuid,
    randomUUID()
  )
})

SET annot += apoc.map.removeKeys(
  apoc.convert.toMap(property),
  ['attributes', 'uuid', 'guid']
)

SET annot += CASE
  WHEN property.attributes IS NULL THEN {}
  ELSE apoc.convert.toMap(property.attributes)
END

SET annot.startIndex = CASE
      WHEN property.startIndex IS NULL THEN null
      ELSE toInteger(property.startIndex)
    END,
    annot.endIndex = CASE
      WHEN property.endIndex IS NULL THEN null
      ELSE toInteger(property.endIndex)
    END

SET annot.sameAs =
  CASE
    WHEN annot.sameAs IS NULL THEN null
    ELSE [x IN split(trim(toString(annot.sameAs)), ' ') WHERE trim(x) <> '']
  END

MERGE (commentText)-[:HAS_ANNOTATION]->(annot)
RETURN count(annot) AS importedCommentTextAnnotations;


// [STEP L10] Normalize annotation types
MATCH (annot:Annotation)
WHERE annot.teiType IS NOT NULL

SET annot.type =
  CASE
    WHEN annot.type IS NULL OR trim(toString(annot.type)) = ''
    THEN annot.teiType

    WHEN annot.type = annot.teiType
    THEN annot.type

    WHEN annot.type STARTS WITH annot.teiType + '-'
    THEN annot.type

    ELSE annot.teiType + '-' + annot.type
  END

RETURN
  annot.teiType AS teiType,
  annot.type AS type,
  count(*) AS count
ORDER BY teiType, type;


// [STEP L11] Link commented annotations to editorial comments
MATCH (annot:Annotation {type: 'commented'})
WHERE annot.key IS NOT NULL

MATCH (commentText:Text:Content {
  uuid: annot.key
})

MERGE (annot)-[:REFERS_TO]->(commentText)
RETURN count(annot) AS linkedCommentedAnnotations;


// [STEP L12] Link rs-comment cross-references with source witnesses
MATCH (sourceAnnot:Annotation {type: 'rs-comment'})
WHERE sourceAnnot.key IS NOT NULL

WITH sourceAnnot, split(sourceAnnot.key, '/#') AS parts
WITH
  sourceAnnot,
  parts[0] AS sourceWitnessUuid,
  parts[1] AS commentUuid

MATCH (:Witness:Collection {uuid: sourceWitnessUuid})<-[:PART_OF]-(sourceText:Text:Content)

MATCH (commentText:Text:Content {
  uuid: commentUuid
})

MERGE (sourceAnnot)-[:REFERS_TO]->(commentText)
RETURN count(sourceAnnot) AS linkedCommentCrossRefs;


// [STEP L13] Link remaining rs-comment cross-references
MATCH (sourceAnnot:Annotation {type: 'rs-comment'})
WHERE sourceAnnot.key IS NOT NULL

WITH sourceAnnot, split(sourceAnnot.key, '/#') AS parts
WITH
  sourceAnnot,
  parts[1] AS commentUuid

MATCH (commentText:Text:Content {
  uuid: commentUuid
})

MERGE (sourceAnnot)-[:REFERS_TO]->(commentText)
RETURN count(sourceAnnot) AS linkedCommentCrossRefsFallback;


// [STEP L14] Link entity references from annotation keys
CALL apoc.periodic.iterate(
  '
  MATCH (annot:Annotation)
  WHERE annot.key IS NOT NULL
  UNWIND split(annot.key, " ") AS rawKey
  WITH annot, replace(rawKey, "#", "") AS key
  WHERE key <> ""
  RETURN annot, key
  ',
  '
  MATCH (entity:Entity {uuid: key})
  MERGE (annot)-[:REFERS_TO]->(entity)
  ',
  {batchSize: 2000}
);


// [STEP L15] Link letter, witness and text references
MATCH (annot:Annotation {type: 'rs-letter'})
WHERE annot.key IS NOT NULL

WITH annot, replace(annot.key, "#", "") AS uuid

OPTIONAL MATCH (letter:Letter:Collection {uuid: uuid})
OPTIONAL MATCH (witness:Witness:Collection {uuid: uuid})
OPTIONAL MATCH (textNode:Text:Content {uuid: uuid})

WITH annot, coalesce(letter, witness, textNode) AS target
WHERE target IS NOT NULL

MERGE (annot)-[:REFERS_TO]->(target)

RETURN count(annot) AS linkedLetterRefs;


// [STEP L16] Remove resolved annotation keys
MATCH (a:Annotation)
WHERE a.key IS NOT NULL
REMOVE a.key
RETURN count(a) AS cleanedAnnotationKeys;
