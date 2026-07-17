// [STEP C01] Import corpora and corpus hierarchy
CALL apoc.load.json(
  'https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/feature-model-revision/data/json/sections.json'
)
YIELD value AS json

CALL (json) {
  UNWIND json.nodes AS sourceNode

  CREATE (corpus:Corpus:Collection {
    uuid: sourceNode.uuid,
    label: sourceNode.label
  })

  RETURN count(corpus) AS importedCorpora
}

CALL (json) {
  UNWIND json.edges AS edge

  MATCH (source:Corpus:Collection {
    uuid: edge.source
  })

  MATCH (target:Corpus:Collection {
    uuid: edge.target
  })

  CREATE (source)-[:PART_OF]->(target)

  RETURN count(*) AS importedCorpusRelations
}

RETURN
  importedCorpora,
  importedCorpusRelations;


// [STEP C02] Import letters, documents and figures
:auto
CALL apoc.load.json(
  'https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/feature-model-revision/data/json/letters.json',
  '$.record[*]',
  {
    pathOptions: []
  }
)
YIELD value AS record

WITH record
WHERE record.metadata.generalMetadataIsPresent = true
  AND trim(
    coalesce(
      toString(
        record.metadata.generalMetadata.attributes.uuid
      ),
      ''
    )
  ) <> ''

CALL (record) {
  WITH
    record.metadata.generalMetadata AS generalMetadata,
    record.metadata.communication AS communication

  MERGE (resource:Collection {
    uuid: generalMetadata.attributes.uuid
  })

  SET resource += apoc.map.clean(
    apoc.map.merge(
      apoc.convert.toMap(generalMetadata.attributes),
      {
        xmlDownload: communication.attributes.xmlDownload
      }
    ),
    [],
    ['', null]
  )

  FOREACH (_ IN CASE
    WHEN generalMetadata.nodeLabel = 'Letter'
    THEN [1]
    ELSE []
  END |
    SET resource:Letter
  )

  FOREACH (_ IN CASE
    WHEN generalMetadata.nodeLabel = 'Document'
    THEN [1]
    ELSE []
  END |
    SET resource:Document
  )

  FOREACH (_ IN CASE
    WHEN generalMetadata.nodeLabel = 'Figure'
    THEN [1]
    ELSE []
  END |
    SET resource:Figure
  )
} IN TRANSACTIONS OF 100 ROWS

RETURN count(*) AS processedResourceRecords;


// [STEP C03] Create all variants listed by their parent resources
:auto
CALL apoc.load.json(
  'https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/feature-model-revision/data/json/letters.json',
  '$.record[*]',
  {
    pathOptions: []
  }
)
YIELD value AS record

WITH record
WHERE record.metadata.generalMetadataIsPresent = true
  AND trim(
    coalesce(
      toString(
        record.metadata.generalMetadata.attributes.uuid
      ),
      ''
    )
  ) <> ''

WITH
  record.metadata.generalMetadata.attributes.uuid AS resourceUuid,
  coalesce(
    apoc.convert.toList(
      record.metadata.generalMetadata.variants
    ),
    []
  ) AS variantUuids

UNWIND variantUuids AS variantUuid

WITH
  resourceUuid,
  variantUuid
WHERE trim(
  coalesce(
    toString(variantUuid),
    ''
  )
) <> ''

CALL (
  resourceUuid,
  variantUuid
) {
  MATCH (resource:Collection {
    uuid: resourceUuid
  })

  MERGE (variant:Variant:Collection {
    uuid: variantUuid
  })

  MERGE (variant)-[:PART_OF]->(resource)
} IN TRANSACTIONS OF 100 ROWS

RETURN count(*) AS processedVariantRelations;


// [STEP C04] Import metadata for every variant record
:auto
CALL apoc.load.json(
  'https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/feature-model-revision/data/json/letters.json',
  '$.record[*]',
  {
    pathOptions: []
  }
)
YIELD value AS record

WITH
  record.metadata.variantMetadata.attributes AS variantAttributes

WHERE trim(
  coalesce(
    toString(variantAttributes.uuid),
    ''
  )
) <> ''

CALL (variantAttributes) {
  MERGE (variant:Variant:Collection {
    uuid: variantAttributes.uuid
  })

  SET variant += apoc.map.clean(
    apoc.convert.toMap(variantAttributes),
    [],
    ['', null]
  )
} IN TRANSACTIONS OF 100 ROWS

RETURN count(*) AS processedVariantRecords;


// [STEP C05] Import abstracts with texts and annotations
:auto
CALL apoc.load.json(
  'https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/feature-model-revision/data/json/letters.json',
  '$.record[*]',
  {
    pathOptions: []
  }
)
YIELD value AS record

WITH record
WHERE record.metadata.generalMetadataIsPresent = true
  AND record.metadata.generalMetadata.nodeLabel = 'Letter'
  AND record.metadata.variantMetadata.attributes.isReference = true
  AND trim(
    coalesce(
      toString(record.texts.abstract.text),
      ''
    )
  ) <> ''

CALL (record) {
  MATCH (letter:Letter:Collection {
    uuid: record.metadata.generalMetadata.attributes.uuid
  })

  WITH
    letter,
    record.texts.abstract AS abstract

  CREATE (abstractCollection:Abstract:Collection {
    uuid: randomUUID(),
    label: 'Abstract zu ' + coalesce(
      letter.label,
      letter.uuid
    )
  })

  CREATE (abstractCollection)-[:PART_OF]->(letter)

  CREATE (textNode:Text:Content {
    uuid: CASE
      WHEN abstract.uuid IS NOT NULL
        AND trim(toString(abstract.uuid)) <> ''
      THEN trim(toString(abstract.uuid))

      ELSE randomUUID()
    END,
    text: abstract.text
  })

  CREATE (textNode)-[:PART_OF]->(
    abstractCollection
  )

  WITH
    textNode,
    abstract

  UNWIND coalesce(
    apoc.convert.toList(abstract.properties),
    []
  ) AS property

  WITH
    textNode,
    property,
    apoc.convert.toMap(property) AS propertyMap,
    coalesce(
      apoc.convert.toMap(property.attributes),
      {}
    ) AS attributes

  MERGE (annotation:Annotation {
    uuid: CASE
      WHEN property.uuid IS NOT NULL
        AND trim(toString(property.uuid)) <> ''
      THEN trim(toString(property.uuid))

      ELSE randomUUID()
    END
  })

  SET annotation += apoc.map.removeKeys(
    propertyMap,
    [
      'attributes',
      'uuid',
      'guid',
      'startIndex',
      'endIndex'
    ]
  )

  SET annotation += attributes

  SET
    annotation.startIndex = CASE
      WHEN property.startIndex IS NULL
      THEN null
      ELSE toInteger(property.startIndex)
    END,
    annotation.endIndex = CASE
      WHEN property.endIndex IS NULL
      THEN null
      ELSE toInteger(property.endIndex)
    END

  SET annotation.type = CASE
    WHEN property.teiType IS NULL
    THEN annotation.type

    WHEN annotation.type IS NULL
      OR trim(toString(annotation.type)) = ''
    THEN property.teiType

    WHEN annotation.type = property.teiType
    THEN annotation.type

    WHEN annotation.type STARTS WITH property.teiType + '-'
    THEN annotation.type

    ELSE property.teiType + '-' + annotation.type
  END

  MERGE (textNode)-[:HAS_ANNOTATION]->(
    annotation
  )
} IN TRANSACTIONS OF 5 ROWS

RETURN count(*) AS processedAbstractRecords;


// [STEP C06] Import variant main texts and annotations
:auto
CALL apoc.load.json(
  'https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/feature-model-revision/data/json/letters.json',
  '$.record[*]',
  {
    pathOptions: []
  }
)
YIELD value AS record

WITH
  record.metadata.variantMetadata.attributes.uuid AS variantUuid,
  record.texts.variant.main_text AS mainText

WHERE trim(
  coalesce(
    toString(variantUuid),
    ''
  )
) <> ''
  AND mainText IS NOT NULL
  AND mainText.text IS NOT NULL

CALL (
  variantUuid,
  mainText
) {
  MATCH (variant:Variant:Collection {
    uuid: variantUuid
  })

  CREATE (textNode:Text:Content {
    uuid: CASE
      WHEN mainText.uuid IS NOT NULL
        AND trim(toString(mainText.uuid)) <> ''
      THEN trim(toString(mainText.uuid))

      ELSE randomUUID()
    END
  })

  SET textNode += apoc.map.clean(
    {
      text: mainText.text
    },
    [],
    ['', null]
  )

  CREATE (textNode)-[:PART_OF]->(variant)

  WITH
    textNode,
    mainText

  UNWIND coalesce(
    apoc.convert.toList(mainText.properties),
    []
  ) AS property

  WITH
    textNode,
    property,
    apoc.convert.toMap(property) AS propertyMap,
    coalesce(
      apoc.convert.toMap(property.attributes),
      {}
    ) AS attributes

  CREATE (annotation:Annotation {
    uuid: CASE
      WHEN property.uuid IS NOT NULL
        AND trim(toString(property.uuid)) <> ''
      THEN trim(toString(property.uuid))

      ELSE randomUUID()
    END
  })

  SET annotation += apoc.map.removeKeys(
    propertyMap,
    [
      'attributes',
      'uuid',
      'guid',
      'startIndex',
      'endIndex'
    ]
  )

  SET annotation += attributes

  SET
    annotation.startIndex = CASE
      WHEN property.startIndex IS NULL
      THEN null

      ELSE toInteger(property.startIndex)
    END,
    annotation.endIndex = CASE
      WHEN property.endIndex IS NULL
      THEN null

      ELSE toInteger(property.endIndex)
    END

  SET annotation.type = CASE
    WHEN property.teiType IS NULL
    THEN annotation.type

    WHEN annotation.type IS NULL
      OR trim(toString(annotation.type)) = ''
    THEN property.teiType

    WHEN annotation.type = property.teiType
    THEN annotation.type

    WHEN annotation.type STARTS WITH property.teiType + '-'
    THEN annotation.type

    ELSE property.teiType + '-' + annotation.type
  END

  CREATE (textNode)-[:HAS_ANNOTATION]->(
    annotation
  )
} IN TRANSACTIONS OF 5 ROWS

RETURN count(*) AS processedMainTexts;


// [STEP C07] Import variant editorial notes as annotations
:auto
CALL apoc.load.json(
  'https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/feature-model-revision/data/json/letters.json',
  '$.record[*]',
  {
    pathOptions: []
  }
)
YIELD value AS record

WITH
  record.metadata.variantMetadata.attributes.uuid AS variantUuid,
  record.texts.note AS note

WHERE trim(
  coalesce(
    toString(variantUuid),
    ''
  )
) <> ''
  AND trim(
    coalesce(
      toString(note.text),
      ''
    )
  ) <> ''

CALL (
  variantUuid,
  note
) {
  MATCH (variant:Variant:Collection {
    uuid: variantUuid
  })

  CREATE (editorialAnnotation:Annotation {
    uuid: CASE
      WHEN note.uuid IS NOT NULL
        AND trim(toString(note.uuid)) <> ''
      THEN trim(toString(note.uuid))

      ELSE randomUUID()
    END,
    type: 'editorial_comment'
  })

  CREATE (variant)-[:HAS_ANNOTATION]->(
    editorialAnnotation
  )

  CREATE (noteText:Text:Content {
    uuid: randomUUID(),
    text: note.text
  })

  CREATE (editorialAnnotation)-[:REFERS_TO]->(
    noteText
  )

  WITH
    noteText,
    note

  UNWIND coalesce(
    apoc.convert.toList(note.properties),
    []
  ) AS property

  WITH
    noteText,
    property,
    apoc.convert.toMap(property) AS propertyMap,
    coalesce(
      apoc.convert.toMap(property.attributes),
      {}
    ) AS attributes

  CREATE (annotation:Annotation {
    uuid: CASE
      WHEN property.uuid IS NOT NULL
        AND trim(toString(property.uuid)) <> ''
      THEN trim(toString(property.uuid))

      ELSE randomUUID()
    END
  })

  SET annotation += apoc.map.removeKeys(
    propertyMap,
    [
      'attributes',
      'uuid',
      'guid',
      'startIndex',
      'endIndex'
    ]
  )

  SET annotation += attributes

  SET
    annotation.startIndex = CASE
      WHEN property.startIndex IS NULL
      THEN null

      ELSE toInteger(property.startIndex)
    END,
    annotation.endIndex = CASE
      WHEN property.endIndex IS NULL
      THEN null

      ELSE toInteger(property.endIndex)
    END

  SET annotation.type = CASE
    WHEN property.teiType IS NULL
    THEN annotation.type

    WHEN annotation.type IS NULL
      OR trim(toString(annotation.type)) = ''
    THEN property.teiType

    WHEN annotation.type = property.teiType
    THEN annotation.type

    WHEN annotation.type STARTS WITH property.teiType + '-'
    THEN annotation.type

    ELSE property.teiType + '-' + annotation.type
  END

  CREATE (noteText)-[:HAS_ANNOTATION]->(
    annotation
  )
} IN TRANSACTIONS OF 5 ROWS

RETURN count(*) AS processedEditorialNotes;


// [STEP C08] Import editorial comments and their annotations
:auto
CALL apoc.load.json(
  'https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/feature-model-revision/data/json/letters.json',
  '$.record[*]',
  {
    pathOptions: []
  }
)
YIELD value AS record

UNWIND coalesce(
  apoc.convert.toList(
    record.texts.variant.editorial_comments
  ),
  []
) AS comment

WITH comment
WHERE trim(
  coalesce(
    toString(comment.uuid),
    ''
  )
) <> ''

CALL (comment) {
  MERGE (commentText:Text:Content {
    uuid: comment.uuid
  })

  SET commentText += apoc.map.clean(
    {
      text: comment.text
    },
    [],
    ['', null]
  )

  WITH
    commentText,
    comment

  UNWIND coalesce(
    apoc.convert.toList(comment.properties),
    []
  ) AS property

  WITH
    commentText,
    property,
    apoc.convert.toMap(property) AS propertyMap,
    coalesce(
      apoc.convert.toMap(property.attributes),
      {}
    ) AS attributes

  MERGE (annotation:Annotation {
    uuid: CASE
      WHEN property.uuid IS NOT NULL
        AND trim(toString(property.uuid)) <> ''
      THEN trim(toString(property.uuid))

      ELSE randomUUID()
    END
  })

  SET annotation += apoc.map.removeKeys(
    propertyMap,
    [
      'attributes',
      'uuid',
      'guid',
      'startIndex',
      'endIndex'
    ]
  )

  SET annotation += attributes

  SET
    annotation.startIndex = CASE
      WHEN property.startIndex IS NULL
      THEN null
      ELSE toInteger(property.startIndex)
    END,
    annotation.endIndex = CASE
      WHEN property.endIndex IS NULL
      THEN null
      ELSE toInteger(property.endIndex)
    END

  SET annotation.type = CASE
    WHEN property.teiType IS NULL
    THEN annotation.type

    WHEN annotation.type IS NULL
      OR trim(toString(annotation.type)) = ''
    THEN property.teiType

    WHEN annotation.type = property.teiType
    THEN annotation.type

    WHEN annotation.type STARTS WITH property.teiType + '-'
    THEN annotation.type

    ELSE property.teiType + '-' + annotation.type
  END

  MERGE (commentText)-[:HAS_ANNOTATION]->(
    annotation
  )
} IN TRANSACTIONS OF 5 ROWS

RETURN count(*) AS processedEditorialComments;


// [STEP C09] Import corpus introductions
UNWIND [
  {
    corpusUuid: 'ed_f13a5020-2370-4d65-917c-325ca9e77f31',
    file: 'Lubieniecki.json'
  },
  {
    corpusUuid: 'ed_8084d019-3192-4c14-9b8e-9892e912590b',
    file: 'Lubieniecki_Hevelius.json'
  },
  {
    corpusUuid: 'ed_81d51ae1-2f85-4e86-8f7e-b758a583d9bb',
    file: 'Lubieniecki_Schletzer.json'
  },
  {
    corpusUuid: 'ed_3cf2a7c4-ce7d-4689-a8b0-bc137e67850b',
    file: 'Lubieniecki_Roetlin.json'
  },
  {
    corpusUuid: 'ed_76e6bd33-3064-44e9-a7be-1c0d8dbf6b0e',
    file: 'Lubieniecki_Reyher.json'
  },
  {
    corpusUuid: 'ed_440bdca6-3003-446d-86ee-27a40c9f548b',
    file: 'Lubieniecki_Grau.json'
  },
  {
    corpusUuid: 'ed_73889c07-4c54-4a95-ba8e-0191c9b9e733',
    file: 'Lubieniecki_Guericke_dae.json'
  },
  {
    corpusUuid: 'ed_df0c6771-1543-4668-8c88-92ca07068cf1',
    file: 'Lubieniecki_Guericke_dj.json'
  },
  {
    corpusUuid: 'ed_9d36824f-209a-427e-ad30-e3c33551ede2',
    file: 'Lubieniecki_Sivers.json'
  },
  {
    corpusUuid: 'ed_e1538210-f69d-4a0f-81f1-9fb5b0f42af3',
    file: 'Lubieniecki_Stegmann_dj.json'
  },
  {
    corpusUuid: 'ed_e8f8738c-0db7-44ea-aca3-bc111a0257b7',
    file: 'Lubieniecki_Rautenstein.json'
  },
  {
    corpusUuid: 'ed_2b69678b-9bf0-4ad8-8a66-77e1b4318af1',
    file: 'Lubieniecki_Placentinus.json'
  },
  {
    corpusUuid: 'ed_c5f314ab-1366-4eb4-94df-46b03baba1f7',
    file: 'Lubieniecki_Mueller.json'
  },
  {
    corpusUuid: 'ed_6954e10e-9907-4ba9-afab-2ce2db8b99c9',
    file: 'Lubieniecki_Olearius.json'
  },
  {
    corpusUuid: 'ed_3f9303b4-aa4b-4ce7-b896-107c782364ab',
    file: 'Lubieniecki_Riccioli.json'
  },
  {
    corpusUuid: 'ed_5ea511d4-9a0d-42e9-b20f-65629f670cb6',
    file: 'Lubieniecki_Boulliau.json'
  },
  {
    corpusUuid: 'ed_cad0bf7d-7511-44ac-a743-32815e95013d',
    file: 'Ruarus_Kirchmann.json'
  },
  {
    corpusUuid: 'ed_566a51cb-a561-490f-83e2-0786f9f0fec8',
    file: 'Ruarus_Peuschel.json'
  }
] AS source

CALL apoc.load.json(
  'https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/main/meta-texts/section-introductions/'
  + source.file
)
YIELD value AS json

MATCH (corpus:Corpus:Collection {
  uuid: source.corpusUuid
})

CREATE (textNode:Text:Content {
  uuid: CASE
    WHEN json.uuid IS NOT NULL
      AND trim(toString(json.uuid)) <> ''
    THEN trim(toString(json.uuid))

    ELSE randomUUID()
  END,
  text: json.text
})

CREATE (textNode)-[:PART_OF]->(corpus)

WITH
  textNode,
  json

UNWIND coalesce(
  apoc.convert.toList(json.properties),
  []
) AS property

WITH
  textNode,
  property,
  apoc.convert.toMap(property) AS propertyMap,
  coalesce(
    apoc.convert.toMap(property.attributes),
    {}
  ) AS attributes

MERGE (annotation:Annotation {
  uuid: CASE
    WHEN property.uuid IS NOT NULL
      AND trim(toString(property.uuid)) <> ''
    THEN trim(toString(property.uuid))

    ELSE randomUUID()
  END
})

SET annotation += apoc.map.removeKeys(
  propertyMap,
  [
    'attributes',
    'uuid',
    'guid',
    'startIndex',
    'endIndex'
  ]
)

SET annotation += attributes

SET
  annotation.startIndex = CASE
    WHEN property.startIndex IS NULL
    THEN null
    ELSE toInteger(property.startIndex)
  END,
  annotation.endIndex = CASE
    WHEN property.endIndex IS NULL
    THEN null
    ELSE toInteger(property.endIndex)
  END

SET annotation.type = CASE
  WHEN property.teiType IS NULL
  THEN annotation.type

  WHEN annotation.type IS NULL
    OR trim(toString(annotation.type)) = ''
  THEN property.teiType

  WHEN annotation.type = property.teiType
  THEN annotation.type

  WHEN annotation.type STARTS WITH property.teiType + '-'
  THEN annotation.type

  ELSE property.teiType + '-' + annotation.type
END

MERGE (textNode)-[:HAS_ANNOTATION]->(
  annotation
)

RETURN
  count(DISTINCT textNode) AS importedIntroductionTexts,
  count(annotation) AS importedIntroductionAnnotations;


// [STEP C09] Import correspondence annotations
:auto
CALL apoc.load.json(
  'https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/feature-model-revision/data/json/letters.json',
  '$.record[*]',
  {
    pathOptions: []
  }
)
YIELD value AS record

WITH record
WHERE record.metadata.generalMetadataIsPresent = true
  AND record.metadata.generalMetadata.nodeLabel = 'Letter'
  AND record.metadata.variantMetadata.attributes.isReference = true

UNWIND coalesce(
  apoc.convert.toList(
    record.metadata.generalMetadata.correspDesc.correspAction
  ),
  []
) AS action

CALL (record, action) {
  MATCH (letter:Letter:Collection {
    uuid: record.metadata.generalMetadata.attributes.uuid
  })

  WITH
    letter,
    action,
    apoc.convert.toMap(action.attributes) AS attributes

  MERGE (annotation:Annotation {
    uuid: CASE
      WHEN action.uuid IS NOT NULL
        AND trim(toString(action.uuid)) <> ''
      THEN trim(toString(action.uuid))

      WHEN attributes.uuid IS NOT NULL
        AND trim(toString(attributes.uuid)) <> ''
      THEN trim(toString(attributes.uuid))

      ELSE randomUUID()
    END
  })

  SET annotation += apoc.map.clean(
    apoc.map.removeKeys(
      attributes,
      ['uuid']
    ),
    [],
    ['', null]
  )

  MERGE (letter)-[:HAS_ANNOTATION]->(
    annotation
  )

  WITH
    annotation,
    action

  UNWIND coalesce(
    apoc.convert.toList(
      action.outgoingRelations.relation
    ),
    []
  ) AS relation

  MATCH (target:Entity {
    uuid: relation.uuid
  })

  CALL apoc.create.relationship(
    annotation,
    relation.relationType,
    {},
    target
  )
  YIELD rel

  RETURN count(rel) AS importedRelations
} IN TRANSACTIONS OF 20 ROWS

RETURN count(*) AS processedCorrespondenceActions;


// [STEP C10] Connect letters only to their particulars
:auto
CALL apoc.load.json(
  'https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/feature-model-revision/data/json/letters.json',
  '$.record[*]',
  {
    pathOptions: []
  }
)
YIELD value AS record

WITH record
WHERE record.metadata.generalMetadataIsPresent = true
  AND record.metadata.generalMetadata.nodeLabel = 'Letter'
  AND record.metadata.variantMetadata.attributes.isReference = true

UNWIND coalesce(
  apoc.convert.toList(
    record.metadata.communication.outgoingRelations.relation
  ),
  []
) AS relation

WITH
  record,
  relation
WHERE relation.relationType = 'PART_OF'
  AND relation.targetNodeType = 'Corpus'
  AND trim(
    coalesce(
      toString(relation.uuid),
      ''
    )
  ) <> ''

MATCH (particular:Corpus:Collection {
  uuid: relation.uuid
})

WHERE NOT EXISTS {
  MATCH (:Corpus:Collection)-[:PART_OF]->(
    particular
  )
}

CALL (record, particular) {
  MATCH (letter:Letter:Collection {
    uuid: record.metadata.generalMetadata.attributes.uuid
  })

  MERGE (letter)-[:PART_OF]->(particular)
} IN TRANSACTIONS OF 250 ROWS

RETURN count(*) AS processedParticularRelations;


// [STEP C11] Import attachment collections
:auto
CALL apoc.load.json(
  'https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/feature-model-revision/data/json/letters.json',
  '$.record[*]',
  {
    pathOptions: []
  }
)
YIELD value AS record

WITH
  record,
  coalesce(
    apoc.convert.toList(
      record.metadata.communication.attachments
    ),
    []
  ) AS attachmentUuids

WHERE record.metadata.generalMetadataIsPresent = true
  AND record.metadata.generalMetadata.nodeLabel = 'Letter'
  AND record.metadata.variantMetadata.attributes.isReference = true
  AND size(attachmentUuids) > 0

CALL (record, attachmentUuids) {
  MATCH (letter:Letter:Collection {
    uuid: record.metadata.generalMetadata.attributes.uuid
  })

  CREATE (attachmentGroup:Attachment:Collection {
    uuid: randomUUID(),
    label: 'Attachments zu ' + coalesce(
      letter.label,
      letter.uuid
    )
  })

  CREATE (attachmentGroup)-[:PART_OF]->(
    letter
  )

  WITH
    attachmentGroup,
    attachmentUuids

  UNWIND attachmentUuids AS attachmentUuid

  MATCH (attachment:Collection {
    uuid: attachmentUuid
  })

  MERGE (attachment)-[:PART_OF]->(
    attachmentGroup
  )
} IN TRANSACTIONS OF 20 ROWS

RETURN count(*) AS processedAttachmentGroups;


// [STEP C12] Resolve annotation references
:auto
MATCH (annotation:Annotation)
WHERE trim(
  coalesce(
    toString(annotation.key),
    ''
  )
) <> ''

UNWIND split(
  trim(toString(annotation.key)),
  ' '
) AS rawKey

WITH
  annotation,
  CASE
    WHEN annotation.type = 'commented'
    THEN 'comment'

    WHEN annotation.type = 'rs-comment'
      AND rawKey CONTAINS '/#'
    THEN 'comment'

    ELSE 'generic'
  END AS targetKind,
  CASE
    WHEN annotation.type = 'rs-comment'
      AND rawKey CONTAINS '/#'
    THEN split(rawKey, '/#')[1]

    ELSE replace(rawKey, '#', '')
  END AS targetUuid

WHERE trim(
  coalesce(
    targetUuid,
    ''
  )
) <> ''

CALL (
  annotation,
  targetKind,
  targetUuid
) {
  OPTIONAL MATCH (entity:Entity {
    uuid: targetUuid
  })
  WHERE targetKind = 'generic'

  OPTIONAL MATCH (collection:Collection {
    uuid: targetUuid
  })
  WHERE targetKind = 'generic'

  OPTIONAL MATCH (commentText:Text:Content {
    uuid: targetUuid
  })
  WHERE targetKind = 'comment'

  FOREACH (_ IN CASE
    WHEN entity IS NULL
    THEN []
    ELSE [1]
  END |
    MERGE (annotation)-[:REFERS_TO]->(entity)
  )

  FOREACH (_ IN CASE
    WHEN collection IS NULL
    THEN []
    ELSE [1]
  END |
    MERGE (annotation)-[:REFERS_TO]->(
      collection
    )
  )

  FOREACH (_ IN CASE
    WHEN commentText IS NULL
    THEN []
    ELSE [1]
  END |
    MERGE (annotation)-[:REFERS_TO]->(
      commentText
    )
  )
} IN TRANSACTIONS OF 250 ROWS

RETURN count(*) AS processedAnnotationReferences;


// [STEP C13] Remove resolved source keys
:auto
MATCH (annotation:Annotation)
WHERE annotation.key IS NOT NULL

CALL (annotation) {
  REMOVE annotation.key
} IN TRANSACTIONS OF 1000 ROWS

RETURN count(*) AS cleanedAnnotationKeys;
