<h1 align="center">Installation Guideline - OAI FH 7.2 on Vanilla Kubernetes</h1>
<hr>


## Project description

**Project Name:** OAI FH 7.2 on Vanilla Kubernetes

**Description:** Something something

**Key Features:**

- Feature 1: [Brief description]
- Feature 2: [Brief description]
- Feature 3: [Brief description]

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
| Deploy OAI 7.2 Chart                    | run script `                                          |                                                              |                    |



## System Architecture

**Important Components to Include in System Architecture (O-RAN O-DU Architecture Pattern):**

1. **Master Node**
2. **Worker Node**

```mermaid

```

## Repository Structure

> [!NOTE]
>
> 1. 

```
tree command
```

## Minimum Specification Requirements

| Component        | Requirement               |
| ---------------- | ------------------------- |
| Operating System | Ubuntu 22.04 or higher    |
| CPU              | 2 GHz dual-core processor |
| Memory           | 4 GB RAM                  |
| GCC Version      | 7.5 or higher             |
| Python Version   | 3.6 or higher             |
| Kubernetes       | 1.18 or higher            |
|                  |                           |

## Table of Paramaters

> [!NOTE]
> **Parameter Comparison Guidelines:**
>
> 1. **Standards Compliance** - All vendor implementations must maintain backward compatibility with 3GPP standards
> 2. **Performance Enhancement** - Vendor-specific features often provide performance improvements beyond standard requirements
> 3. **Interoperability** - Ensure vendor-specific parameters don't compromise network interoperability
> 4. **Documentation** - Always refer to the latest version of specifications as standards evolve
> 5. **Testing** - Validate vendor-specific implementations against 3GPP test cases

### Inputs Parameters

| Parameter Name                  | Description                                    | 3GPP Reference                                                                      | Samsung                                                         |
| ------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| **Cell ID**               | Unique identifier for each cell in the network | [TS 36.211 Section 6.11](https://www.3gpp.org/ftp/Specs/archive/36_series/36.211/)     | CellId                                                          |
| **Tracking Area Code**    | Area identifier for location management        | [TS 23.003 Section 19.4.2.3](https://www.3gpp.org/ftp/Specs/archive/23_series/23.003/) | TAC_Optimized                                                   |
| **PLMN ID**               | Public Land Mobile Network identifier          | [TS 23.003 Section 2.2](https://www.3gpp.org/ftp/Specs/archive/23_series/23.003/)      | PLMN_Code                                                       |
| **Bandwidth**             | Radio channel bandwidth allocation             | [TS 36.104 Section 5.6](https://www.3gpp.org/ftp/Specs/archive/36_series/36.104/)      | [Extended_BW](https://www.samsung.com/us/business/networks/)       |
| **Transmission Power**    | Maximum transmission power per antenna         | [TS 36.101 Section 6.2.5](https://www.3gpp.org/ftp/Specs/archive/36_series/36.101/)    | [TxPwr_Adaptive](https://www.zte.com.cn/global/products/wireless/) |
| **Antenna Configuration** | Number of transmit/receive antenna elements    | [TS 36.213 Section 7.1](https://www.3gpp.org/ftp/Specs/archive/36_series/36.213/)      | MIMO_Setup                                                      |

Output Parameters

| Paremeters |      |      |
| ---------- | ---- | ---- |
|            |      |      |
|            |      |      |
|            |      |      |



## Message Sequence Chart (MSC)

> [!NOTE]
> **MSC Should Include:**
>
> 1. **Actors/Components** - All participating systems and users
> 2. **Message Flow** - Sequential communication between components
> 3. **Timing** - Order of operations and dependencies
> 4. **Error Handling** - Alternative flows and error scenarios
> 5. **Data Validation** - Authentication and authorization steps



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
