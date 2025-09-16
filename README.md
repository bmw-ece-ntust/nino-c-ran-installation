<h1 align="center">Installation Guideline - OAI FH 7.2 on Vanilla Kubernetes</h1>
<hr>


## Project description

**Project Name:** OAI FH 7.2 on Vanilla Kubernetes

**Description:** Something something

**Key Features:**

- Automated Deployment and Management of GNB Software on Cloud Environment

**Target Users:** [Developers/Researchers/System Administrators/etc.]

> [!CAUTION]
> Make this document private by default. Only make it public after publishing the project.
>
> Request access with the GitHub admin in our group.

> [!NOTE]
> **Purpose of Installation Guide:**
> This guide focuses on setup, configuration, and getting the system running on your local environment or target deployment system.

## Table of Contents



## Remote Access Methods



### SSH

```shell
ssh bmw@192.168.8.75
```



## Action Items

Write your installation/integration plan & status in here:

| Step                         | Command/Action                                               | Description                                        | Status |
| ---------------------------- | ------------------------------------------------------------ | -------------------------------------------------- | ------ |
| Check Server Support for SRIOV and NUMA | Human Intervention                                    | Google this up., based on your machine.                      | :white_check_mark: |
| Configure BIOS for SRIOV and NUMA       | Human Intervention                                    | Google this up., based on your machine.                      | :white_check_mark: |
| Install OS for Kubernetes Master Node   | Install RHEL 9                                        |                                                              | :white_check_mark: |
| Install OS for Kubernetes Worker Node   | Install RHEL 9                                        |                                                              | :white_check_mark: |
| Setup Master Node                       | run script `provision/master_setup.sh` on master Node | Turn this node into master node and install necessary components for O-Cloud Operation | :white_check_mark: |
| Setup Worker Node for RT Workload       | run script `provision/worker_setup.sh` on worker Node | Turn this node into worker node and adjust the kernel into RT | :white_check_mark: |
| Build and Publish OAI 7.2 Image         | run script `deployment/build_image.sh`                | You can run this from any machine with internet connection   | :white_check_mark: |
| Deploy OAI 7.2 Chart                    | run script `deployment/deploy_test.sh`                | Deploy Chart of OAI GNB                                      | :white_check_mark: |
|                                         |                                                       |                                                              |                    |



## System Architecture

**Important Components to Include in System Architecture (O-RAN O-DU Architecture Pattern):**

1. **Master Node**
   1. Cilium CNI
   2. Multus CNI
   3. OpenEBS	

2. **Worker Node**
   1. RT Kernel
   2. SRIOV Enabled
   3. 




## Repository Structure

> [!NOTE]
>
> 1. 

```
tree command
```

## Minimum Specification Requirements

| Component        | Requirement                            |
| ---------------- | -------------------------------------- |
| Operating System | Red Hat Enterprise Linux 9.0 or Higher |
| CPU              | 2 GHz, 8-core                          |
| Memory           | 16 GB RAM                              |
| Kubernetes       | 1.28 or higher                         |
| CRI-O            | 1.28 or higher                         |
| HW Motherboard   | Support NUMA                           |
| HW NIC           | Support SRIOV                          |



## Table of Paramaters

> [!NOTE]
> **Parameter Comparison Guidelines:**
>
> 1. 

### Inputs Parameters

| Parameter Name                  | Description                                    | ...                                                                    | ...                                                       |
| ------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------------- |
|                |             |      |      |
|                |             |      |      |
|                |             |      |      |
|                |             |      |      |
|                |             |      |      |
|                |             |      |      |

Output Parameters

| Paremeters |      |      |
| ---------- | ---- | ---- |
|            |      |      |
|            |      |      |
|            |      |      |



## Message Sequence Chart (MSC)

> [!NOTE]
> ...





## Post-Installation Verification

Follow these steps to verify your installation was successful:

1. **Check Application Status:**

   ```bash
   # Check if the application is running
   ps aux | grep app.py
   ```

   **Expected Result:** You should see the process running with PID and resource usage information.
2. **Test Basic Functionality:**

   ```bash
   # Test API endpoint (if applicable)
   curl http://localhost:3000/health
   ```

   **Expected Result:** Response should return `{"status": "OK", "timestamp": "..."}` or similar.
3. **Verify Database Connection:**

   ```bash
   # Run database connectivity test
   python3 -c "from src.main import test_db_connection; test_db_connection()"
   ```

   **Expected Result:** Output should confirm successful database connection.



## Troubleshooting

### Common Issues and Solutions

1. **Issue: Port already in use**

   **Error Message:** `Address already in use: 3000`

   **Solution:**

   ```bash
   # Find process using the port
   sudo lsof -i :3000
   # Kill the process (replace PID with actual process ID)
   kill -9 <PID>
   ```
2. **Issue: Python dependencies not found**

   **Error Message:** `ModuleNotFoundError: No module named 'module_name'`

   **Solution:**

   ```bash
   # Reinstall dependencies
   pip install -r requirements.txt
   # Or install specific package
   pip install module_name
   ```
3. **Issue: Permission denied errors**

   **Error Message:** `Permission denied: '/path/to/file'`

   **Solution:**

   ```bash
   # Fix file permissions
   chmod 755 /path/to/file
   # Or run with appropriate user permissions
   sudo python3 app.py
   ```

## Additional Resources

**Documentation:**

- [Official Project Documentation](https://your-project-docs.com)
- [API Reference Guide](https://your-project-api.com)
- [Configuration Reference](https://your-project-config.com)

**Community Support:**

- [GitHub Issues](https://github.com/your-username/your-repo/issues)
- [Stack Overflow Tag](https://stackoverflow.com/questions/tagged/your-project)
- [Discord Community](https://discord.gg/your-project)

**Contact:**

- **Maintainer:** Your Name (<your.email@example.com>)
- **Support Team:** <support@your-project.com>
- **Emergency Contact:** +1-xxx-xxx-xxxx (for critical issues only)

---

> [!NOTE]
> This installation guide is regularly updated. For the latest version, check the [GitHub repository](https://github.com/your-username/your-repo).
