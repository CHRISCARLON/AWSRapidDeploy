import duckdb
import pyarrow as pa
from typing import Dict, Any
from deltalake import write_deltalake

def handle_file_type(conn: duckdb.DuckDBPyConnection, extension: str, input_path: str) -> pa.Table:
    match extension:
        case "parquet":
            return conn.query(f"""
                SELECT *
                FROM read_parquet('{input_path}')
                LIMIT 100
            """).arrow()
        case "csv":
            return conn.query(f"""
                SELECT *
                FROM read_csv('{input_path}')
                LIMIT 100
            """).arrow()
        case _:
            raise ValueError(f"Unsupported file type: {extension}")

def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for processing S3 events and writing to Delta table.

    Supports parquet and csv files.
    
    Args:
        event: S3 event trigger
        context: Lambda context
    
    Returns:
        Dict containing status code and processing message
    """
    
    # Get bucket and key from the S3 event
    bucket: str = event["Records"][0]["s3"]["bucket"]["name"]
    key: str = event["Records"][0]["s3"]["object"]["key"]

    # Extract file extension
    extension: str = key.split('.')[-1].lower()
    print(f"File extension is: {extension}")
    
    # Initialise DuckDB connection in memory
    conn = duckdb.connect(':memory:')
    print("DUCKDB CONNECTED")
    
    # Install and load httpfs extension for S3 access
    conn.query("""
        INSTALL httpfs;
        LOAD httpfs;
        
        -- Use IAM role credentials
        CREATE SECRET secretaws (
            TYPE S3,
            PROVIDER CREDENTIAL_CHAIN
        );
    """)
    
    # Define input and output paths
    input_path: str = f"s3://{bucket}/{key}"
    output_delta_path: str = "s3://duckdb-lambda-delta-bucket/delta-table"

    # Read parquet file into Arrow table
    df: pa.Table = handle_file_type(conn, extension, input_path)

    print("ARROW TABLE CREATED")
    print(df.take([0,1,2,3,4]).to_pylist())
    print("Total rows:", len(df))
    print(df.describe())
    
    # Write to Delta table
    write_deltalake(
        output_delta_path,
        df,
        mode="append",
        storage_options={
            "AWS_S3_ALLOW_UNSAFE_RENAME": "true"
        }
    )

    print("DELTA LAKE TABLE CREATED")
    
    return {
        'statusCode': 200,
        'body': f'Successfully processed {key}'
    }