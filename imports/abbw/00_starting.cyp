// [STEP 001] Delete all nodes and relationships
CALL apoc.periodic.iterate(
  'MATCH (node) RETURN node',
  'DETACH DELETE node',
  {
    batchSize: 1000
  }
);


// [STEP 002] Delete all existing constraints and indexes
CALL apoc.schema.assert(
  {},
  {},
  true
)
YIELD
  label,
  key

RETURN *;


// [STEP 003] Create UUID constraints
CREATE CONSTRAINT entity_uuid_unique IF NOT EXISTS
FOR (node:Entity)
REQUIRE node.uuid IS UNIQUE;

CREATE CONSTRAINT collection_uuid_unique IF NOT EXISTS
FOR (node:Collection)
REQUIRE node.uuid IS UNIQUE;

CREATE CONSTRAINT content_uuid_unique IF NOT EXISTS
FOR (node:Content)
REQUIRE node.uuid IS UNIQUE;

CREATE CONSTRAINT annotation_uuid_unique IF NOT EXISTS
FOR (node:Annotation)
REQUIRE node.uuid IS UNIQUE;


// [STEP 004] Create lookup indexes
CREATE INDEX entity_label_index IF NOT EXISTS
FOR (node:Entity)
ON (node.label);

CREATE INDEX collection_label_index IF NOT EXISTS
FOR (node:Collection)
ON (node.label);

CREATE INDEX annotation_type_index IF NOT EXISTS
FOR (node:Annotation)
ON (node.type);
