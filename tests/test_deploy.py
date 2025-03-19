# Add your unit tests here
import pytest
import subprocess

# Test if the deployment script runs without errors
def test_deploy_script_runs_without_errors():
    result = subprocess.run(['./deploy.sh'], capture_output=True, text=True)
    assert result.returncode == 0, f"Deployment script failed with error: {result.stderr}"

# Test if the success log file is created
def test_success_log_file_created():
    result = subprocess.run(['./deploy.sh'], capture_output=True, text=True)
    assert 'success_regions.log' in result.stdout, "Success log file not created"

# Test if the failure log file is created
def test_failure_log_file_created():
    result = subprocess.run(['./deploy.sh'], capture_output=True, text=True)
    assert 'failed_regions.log' in result.stdout, "Failure log file not created"

# Test if the deployment log file is created
def test_deployment_log_file_created():
    result = subprocess.run(['./deploy.sh'], capture_output=True, text=True)
    assert 'deployment.log' in result.stdout, "Deployment log file not created"

# Test if the cleanup function works
def test_cleanup_function():
    result = subprocess.run(['./deploy.sh'], capture_output=True, text=True)
    assert 'cleanup_resources' in result.stdout, "Cleanup function did not run"

# Test if the notification mechanism works
def test_notification_mechanism():
    result = subprocess.run(['./deploy.sh'], capture_output=True, text=True)
    assert 'Deployment status' in result.stdout, "Notification mechanism did not work"
