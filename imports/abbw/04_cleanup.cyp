// [STEP F01] Set missing Annotation UUIDs
:auto
MATCH (annotation:Annotation)
WHERE annotation.uuid IS NULL
   OR trim(toString(annotation.uuid)) = ''

CALL (annotation) {
  SET annotation.uuid = randomUUID()
} IN TRANSACTIONS OF 1000 ROWS

RETURN count(*) AS updatedAnnotations;


// [STEP F02] Set missing Collection labels
:auto
MATCH (collection:Collection)
WHERE collection.label IS NULL
   OR trim(toString(collection.label)) = ''

CALL (collection) {
  SET collection.label = CASE
    WHEN collection:Witness
    THEN 'Textzeuge'

    ELSE ''
  END
} IN TRANSACTIONS OF 1000 ROWS

RETURN count(*) AS updatedCollections;
