// [STEP C01] Normalize letter status and editors
MATCH (letter:Letter:Collection)

WITH
  letter,
  CASE
    WHEN letter.status IS NULL
    THEN letter.status

    ELSE CASE toLower(trim(toString(letter.status)))
      WHEN 'draft'
      THEN '2-draft'

      WHEN 'transcription'
      THEN '1-transcription'

      WHEN 'final'
      THEN '0-final'

      ELSE letter.status
    END
  END AS normalizedStatus,
  CASE
    WHEN letter.editor IS NULL
      OR trim(toString(letter.editor)) = ''
    THEN letter.editor

    ELSE trim(
      apoc.text.replace(
        toString(letter.editor),
        '\\s*\\([^)]*\\)\\s*$',
        ''
      )
    )
  END AS editorClean

WITH
  letter,
  normalizedStatus,
  CASE
    WHEN editorClean IS NULL
      OR trim(toString(editorClean)) = ''
    THEN editorClean

    ELSE apoc.text.camelCase(
      toLower(editorClean)
    )
  END AS editorKey

SET
  letter.status = normalizedStatus,
  letter.editor = editorKey

RETURN
  letter.status AS status,
  letter.editor AS editor,
  count(*) AS count
ORDER BY
  status,
  editor;


// [STEP C02] Remove editorial comment texts belonging to draft letters
MATCH (letter:Letter:Collection {
  status: '2-draft'
})

MATCH (letter)<-[:PART_OF]-(:Witness:Collection)
              <-[:PART_OF]-(sourceText:Text:Content)

MATCH (sourceText)-[:HAS_ANNOTATION]->(
  sourceAnnotation:Annotation
)

MATCH (sourceAnnotation)-[:REFERS_TO]->(
  commentText:Text:Content
)

WHERE sourceAnnotation.type IN [
  'rs-comment',
  'commented',
  'seg-comment'
]

OPTIONAL MATCH (commentText)-[:HAS_ANNOTATION]->(
  commentAnnotation:Annotation
)

WITH
  collect(DISTINCT commentText) AS commentTexts,
  collect(DISTINCT commentAnnotation) AS commentAnnotations

WITH
  [node IN commentTexts WHERE node IS NOT NULL]
  + [node IN commentAnnotations WHERE node IS NOT NULL] AS nodesToDelete

UNWIND nodesToDelete AS node

WITH DISTINCT node

DETACH DELETE node

RETURN count(node) AS deletedMetadataCommentTextNodes;


// [STEP C03] Remove main texts and abstracts belonging to draft letters
MATCH (letter:Letter:Collection {
  status: '2-draft'
})

OPTIONAL MATCH (letter)<-[:PART_OF]-(:Witness:Collection)
                       <-[:PART_OF]-(witnessText:Text:Content)

OPTIONAL MATCH (witnessText)-[:HAS_ANNOTATION]->(
  witnessAnnotation:Annotation
)

OPTIONAL MATCH (letter)<-[:PART_OF]-(
  abstractCollection:Abstract:Collection
)

OPTIONAL MATCH (abstractCollection)<-[:PART_OF]-(
  abstractText:Text:Content
)

OPTIONAL MATCH (abstractText)-[:HAS_ANNOTATION]->(
  abstractAnnotation:Annotation
)

WITH
  collect(DISTINCT witnessText) AS witnessTexts,
  collect(DISTINCT witnessAnnotation) AS witnessAnnotations,
  collect(DISTINCT abstractCollection) AS abstractCollections,
  collect(DISTINCT abstractText) AS abstractTexts,
  collect(DISTINCT abstractAnnotation) AS abstractAnnotations

WITH
  [node IN witnessTexts WHERE node IS NOT NULL]
  + [node IN witnessAnnotations WHERE node IS NOT NULL]
  + [node IN abstractCollections WHERE node IS NOT NULL]
  + [node IN abstractTexts WHERE node IS NOT NULL]
  + [node IN abstractAnnotations WHERE node IS NOT NULL] AS nodesToDelete

UNWIND nodesToDelete AS node

WITH DISTINCT node

DETACH DELETE node

RETURN count(node) AS deletedMetadataTextNodes;


// [STEP C04] Remove non-textual annotations from transcription letters
MATCH (letter:Letter:Collection {
  status: '1-transcription'
})

MATCH (letter)<-[:PART_OF]-(:Witness:Collection)
              <-[:PART_OF]-(textNode:Text:Content)

MATCH (textNode)-[:HAS_ANNOTATION]->(
  annotation:Annotation
)

WHERE annotation.type IS NOT NULL
  AND NOT annotation.type IN [
    'p',
    'postscript',
    'div-writingSession',
    'opener',
    'closer',
    'dateline',
    'salute',
    'signed',
    'address',
    'addrLine',
    'head',
    'lg',
    'lg-poem',
    'l',

    'hi',
    'del',
    'add',
    'supplied',
    'subst',
    'choice',
    'orig',
    'expan',
    'corr',
    'ex',
    'metamark',
    'g',
    'abbr',
    'unclear',
    'sic',
    'reg',

    'lb',
    'pb',
    'fw-folNum',
    'gap'
  ]

DETACH DELETE annotation

RETURN count(annotation) AS deletedNonTextualTranscriptionAnnotations;


// [STEP C05] Remove untyped annotations from transcription letters
MATCH (letter:Letter:Collection {
  status: '1-transcription'
})

MATCH (letter)<-[:PART_OF]-(:Witness:Collection)
              <-[:PART_OF]-(textNode:Text:Content)

MATCH (textNode)-[:HAS_ANNOTATION]->(
  annotation:Annotation
)

WHERE annotation.type IS NULL
   OR trim(toString(annotation.type)) = ''

DETACH DELETE annotation

RETURN count(annotation) AS deletedUntypedTranscriptionAnnotations;


// [STEP C06] Remove orphaned editorial comment texts
MATCH (commentText:Text:Content)

WHERE NOT (commentText)-[:PART_OF]->(:Collection)
  AND NOT (commentText)<-[:REFERS_TO]-(:Annotation)

OPTIONAL MATCH (commentText)-[:HAS_ANNOTATION]->(
  commentAnnotation:Annotation
)

WITH
  commentText,
  collect(DISTINCT commentAnnotation) AS commentAnnotations

WITH
  [commentText]
  + [
      annotation IN commentAnnotations
      WHERE annotation IS NOT NULL
    ] AS nodesToDelete

UNWIND nodesToDelete AS node

WITH DISTINCT node

DETACH DELETE node

RETURN count(node) AS deletedOrphanCommentTextNodes;


// [STEP S01] Initialize static entity statistics
MATCH (entity:Entity)

SET
  entity.mentions = 0,
  entity.remarks = 0;


// [STEP S02] Count distinct letter mentions
MATCH (entity:Entity)

OPTIONAL MATCH (entity)<-[:REFERS_TO]-(
  :Annotation {
    type: 'sent'
  }
)<-[:HAS_ANNOTATION]-(sentLetter:Letter:Collection)

WITH
  entity,
  collect(DISTINCT sentLetter) AS sentLetters

OPTIONAL MATCH (entity)<-[:REFERS_TO]-(
  :Annotation {
    type: 'received'
  }
)<-[:HAS_ANNOTATION]-(receivedLetter:Letter:Collection)

WITH
  entity,
  sentLetters,
  collect(DISTINCT receivedLetter) AS receivedLetters

OPTIONAL MATCH (entity)<-[:REFERS_TO]-(:Annotation)
                       <-[:HAS_ANNOTATION]-(textNode:Text:Content)

OPTIONAL MATCH (textNode)-[:PART_OF]->(
  directLetter:Letter:Collection
)

OPTIONAL MATCH (textNode)-[:PART_OF]->(:Witness:Collection)
                         -[:PART_OF]->(
                           witnessLetter:Letter:Collection
                         )

OPTIONAL MATCH (textNode)-[:PART_OF]->(:Abstract:Collection)
                         -[:PART_OF]->(
                           abstractLetter:Letter:Collection
                         )

WITH
  entity,
  sentLetters,
  receivedLetters,
  collect(DISTINCT directLetter) AS directLetters,
  collect(DISTINCT witnessLetter) AS witnessLetters,
  collect(DISTINCT abstractLetter) AS abstractLetters

WITH
  entity,
  [
    letter IN
      sentLetters
      + receivedLetters
      + directLetters
      + witnessLetters
      + abstractLetters
    WHERE letter IS NOT NULL
  ] AS letters

SET entity.mentions = size(
  apoc.coll.toSet(letters)
);


// [STEP S03] Count distinct letter remarks
MATCH (entity:Entity)

OPTIONAL MATCH (entity)<-[:REFERS_TO]-(
  commentEntityAnnotation:Annotation
)<-[:HAS_ANNOTATION]-(commentText:Text:Content)
 <-[:REFERS_TO]-(sourceAnnotation:Annotation)
 <-[:HAS_ANNOTATION]-(sourceText:Text:Content)

OPTIONAL MATCH (sourceText)-[:PART_OF]->(
  directLetter:Letter:Collection
)

OPTIONAL MATCH (sourceText)-[:PART_OF]->(:Witness:Collection)
                           -[:PART_OF]->(
                             witnessLetter:Letter:Collection
                           )

OPTIONAL MATCH (sourceText)-[:PART_OF]->(:Abstract:Collection)
                           -[:PART_OF]->(
                             abstractLetter:Letter:Collection
                           )

WITH
  entity,
  collect(DISTINCT directLetter) AS directLetters,
  collect(DISTINCT witnessLetter) AS witnessLetters,
  collect(DISTINCT abstractLetter) AS abstractLetters

WITH
  entity,
  [
    letter IN
      directLetters
      + witnessLetters
      + abstractLetters
    WHERE letter IS NOT NULL
  ] AS letters

SET entity.remarks = size(
  apoc.coll.toSet(letters)
);
