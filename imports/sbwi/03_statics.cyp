// [STEP S01] Initialize static entity statistics
MATCH (entity:Entity)

SET
  entity.mentions = 0,
  entity.remarks = 0;


// [STEP S02] Count distinct resource mentions
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

OPTIONAL MATCH (textNode)-[:PART_OF]->(:Variant:Collection)
                         -[:PART_OF]->(
                           variantResource:Collection
                         )

OPTIONAL MATCH (textNode)-[:PART_OF]->(:Abstract:Collection)
                         -[:PART_OF]->(
                           abstractLetter:Letter:Collection
                         )

WITH
  entity,
  sentLetters,
  receivedLetters,
  collect(DISTINCT variantResource) AS variantResources,
  collect(DISTINCT abstractLetter) AS abstractLetters

WITH
  entity,
  sentLetters
    + receivedLetters
    + variantResources
    + abstractLetters AS resources

SET entity.mentions = size(
  apoc.coll.toSet(
    [
      resource IN resources
      WHERE resource IS NOT NULL
    ]
  )
);


// [STEP S03] Count distinct resource remarks
MATCH (entity:Entity)

OPTIONAL MATCH (entity)<-[:REFERS_TO]-(:Annotation)
                       <-[:HAS_ANNOTATION]-(
                         commentText:Text:Content
                       )
                       <-[:REFERS_TO]-(
                         sourceAnnotation:Annotation
                       )
                       <-[:HAS_ANNOTATION]-(
                         sourceText:Text:Content
                       )

WHERE sourceAnnotation.type IN [
  'commented',
  'rs-comment',
  'seg-comment'
]

OPTIONAL MATCH (sourceText)-[:PART_OF]->(:Variant:Collection)
                           -[:PART_OF]->(
                             variantResource:Collection
                           )

OPTIONAL MATCH (sourceText)-[:PART_OF]->(:Abstract:Collection)
                           -[:PART_OF]->(
                             abstractLetter:Letter:Collection
                           )

WITH
  entity,
  collect(DISTINCT variantResource) AS variantResources,
  collect(DISTINCT abstractLetter) AS abstractLetters

WITH
  entity,
  variantResources
    + abstractLetters AS resources

SET entity.remarks = size(
  apoc.coll.toSet(
    [
      resource IN resources
      WHERE resource IS NOT NULL
    ]
  )
);
