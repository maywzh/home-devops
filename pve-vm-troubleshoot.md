# PVE 虚拟机故障排查指南 - ubuntu-node3

## 1. 从 PVE 主机层面检查

### 登录到 PVE 主机
```bash
# 通过 SSH 登录到运行 ubuntu-node3 的 PVE 主机
ssh root@<pve-host-ip>
```

### 检查虚拟机状态
```bash
# 查看所有虚拟机状态
qm list

# 查看 ubuntu-node3 的详细状态（假设 VMID 是 120）
qm status <VMID>

# 查看虚拟机配置
qm config <VMID>

# 查看虚拟机进程
ps aux | grep "kvm.*<VMID>"
```

### 检查资源使用情况
```bash
# 查看 PVE 主机资源
free -h
df -h
top

# 查看虚拟机资源使用
qm monitor <VMID>
# 在 monitor 中输入：
# info status
# info cpus
# info balloon
```

## 2. 虚拟机控制台访问

### 通过 PVE Web UI
1. 登录 PVE Web 界面 (https://<pve-host>:8006)
2. 选择 ubuntu-node3 虚拟机
3. 点击 "Console" 查看是否有错误信息

### 通过命令行
```bash
# 连接到虚拟机控制台
qm terminal <VMID>

# 或使用 VNC
qm vncproxy <VMID>
```

## 3. 检查虚拟机日志

```bash
# 查看虚拟机启动日志
journalctl -u pve-guests.service | grep <VMID>

# 查看 QEMU 日志
cat /var/log/pve/qemu-server/<VMID>.log

# 查看最近的任务日志
cat /var/log/pve/tasks/active
```

## 4. 常见问题和解决方案

### 4.1 虚拟机完全无响应

**强制停止虚拟机**
```bash
# 尝试正常停止
qm stop <VMID>

# 如果无响应，强制停止
qm stop <VMID> --skiplock

# 如果还是无法停止，直接 kill 进程
ps aux | grep "kvm.*<VMID>" | grep -v grep | awk '{print $2}' | xargs kill -9
```

### 4.2 磁盘 I/O 问题

**检查存储状态**
```bash
# 检查存储池状态
pvesm status

# 检查磁盘 I/O
iostat -x 1

# 检查虚拟机磁盘
qm rescan
```

### 4.3 内存问题

**检查和调整内存**
```bash
# 查看当前内存分配
qm config <VMID> | grep memory

# 检查是否有内存气球驱动问题
qm monitor <VMID>
# 输入: info balloon

# 临时释放一些内存
qm set <VMID> --balloon 2048
```

### 4.4 CPU 问题

**检查 CPU 使用**
```bash
# 查看虚拟机 CPU 使用
qm monitor <VMID>
# 输入: info cpus

# 检查 CPU 限制
qm config <VMID> | grep cpu
```

## 5. 恢复步骤

### 步骤 1: 尝试软重启
```bash
# 发送 ACPI 关机信号
qm shutdown <VMID>

# 等待 30 秒
sleep 30

# 启动虚拟机
qm start <VMID>
```

### 步骤 2: 强制重启
```bash
# 如果软重启无效
qm stop <VMID> --skiplock
qm unlock <VMID>
qm start <VMID>
```

### 步骤 3: 检查并修复磁盘
```bash
# 在虚拟机停止状态下
# 检查磁盘镜像
qemu-img check /var/lib/vz/images/<VMID>/vm-<VMID>-disk-0.qcow2

# 如果需要修复
qemu-img check -r all /var/lib/vz/images/<VMID>/vm-<VMID>-disk-0.qcow2
```

### 步骤 4: 使用救援模式
```bash
# 添加 CD-ROM 并设置为第一启动
qm set <VMID> --ide2 local:iso/ubuntu-rescue.iso,media=cdrom
qm set <VMID> --boot order=ide2

# 启动进入救援模式
qm start <VMID>
```

## 6. 预防措施

1. **启用 QEMU Guest Agent**
   ```bash
   # 在虚拟机内安装
   apt-get install qemu-guest-agent
   
   # 在 PVE 配置中启用
   qm set <VMID> --agent 1
   ```

2. **设置看门狗**
   ```bash
   qm set <VMID> --watchdog model=i6300esb,action=reset
   ```

3. **定期备份**
   ```bash
   vzdump <VMID> --storage <storage-name>
   ```

## 7. 紧急恢复命令集

```bash
# 快速诊断命令
VMID=<your-vm-id>
echo "=== VM Status ==="
qm status $VMID
echo "=== VM Config ==="
qm config $VMID | grep -E "memory|cores|bootdisk"
echo "=== Process Check ==="
ps aux | grep "kvm.*$VMID" | grep -v grep
echo "=== Recent Logs ==="
tail -20 /var/log/pve/qemu-server/$VMID.log
echo "=== Storage Status ==="
pvesm status
```

## 注意事项

- 在执行任何操作前，确保有虚拟机的备份
- 如果虚拟机包含重要数据，先尝试软重启
- 强制操作可能导致数据损坏
- 考虑在 PVE 集群中迁移虚拟机到其他节点