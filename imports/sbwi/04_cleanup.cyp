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
  SET collection.label = collection.uuid
} IN TRANSACTIONS OF 1000 ROWS

RETURN count(*) AS updatedCollections;


// [STEP F03] Move table start indexes behind preceding headings
:auto
MATCH (content:Content)-[:HAS_ANNOTATION]->(
  table:Annotation {
    type: 'table'
  }
)

MATCH (content)-[:HAS_ANNOTATION]->(
  heading:Annotation {
    type: 'head'
  }
)

WHERE heading.startIndex = table.startIndex
  AND heading.endIndex IS NOT NULL
  AND table.endIndex IS NOT NULL
  AND heading.endIndex < table.endIndex

WITH
  table,
  max(heading.endIndex) AS headingEnd

CALL (
  table,
  headingEnd
) {
  SET table.startIndex = headingEnd + 1
} IN TRANSACTIONS OF 1000 ROWS

RETURN count(*) AS updatedTableAnnotations;


// [STEP F04] Move list start indexes behind preceding headings
:auto
MATCH (content:Content)-[:HAS_ANNOTATION]->(
  list:Annotation {
    type: 'list'
  }
)

MATCH (content)-[:HAS_ANNOTATION]->(
  heading:Annotation {
    type: 'head'
  }
)

WHERE heading.startIndex = list.startIndex
  AND heading.endIndex IS NOT NULL
  AND list.endIndex IS NOT NULL
  AND heading.endIndex < list.endIndex

WITH
  list,
  max(heading.endIndex) AS headingEnd

CALL (
  list,
  headingEnd
) {
  SET list.startIndex = headingEnd + 1
} IN TRANSACTIONS OF 1000 ROWS

RETURN count(*) AS updatedListAnnotations;
