import logging
import sys
import time
import os

def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[logging.StreamHandler(sys.stdout)]
    )

    dummy_env = os.getenv("DUMMY_ENV", "default_value")
    logging.info(f"Starting Cloud Run job test script. DUMMY_ENV={dummy_env}")
    for i in range(5):
        logging.info(f"Processing step {i+1}/5...")
        time.sleep(1)
    logging.info("Cloud Run job test completed successfully.")

if __name__ == "__main__":
    main()
