import logging
import sys
import time

def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[logging.StreamHandler(sys.stdout)]
    )

    logging.info("Starting Cloud Run job test script.")
    for i in range(5):
        logging.info(f"Processing step {i+1}/5...")
        time.sleep(1)
    logging.info("Cloud Run job test completed successfully.")

if __name__ == "__main__":
    main()
