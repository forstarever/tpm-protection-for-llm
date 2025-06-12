# tpm-protection-for-llm

北邮毕设-基于硬件可信根的数据保护技术的设计与实现

### 主要内容
使用TPM硬件可信根为大模型的模型参数文件进行保护。

### 系统架构

1. 用户端：本地用户，将模型上传至云端平台，控制模型密钥
2. 云端：云计算平台，进行模型的训练、推理
3. 第三方CA：对证书进行签发和校验
![image](https://github.com/user-attachments/assets/002372a4-ac38-4370-9046-cf4e1f80f052)

### 主要模块
1. 可信启动
   
   通过TPM度量启动链，并记录到PCR中
   
3. 远程证明
   
   用户端校验云端身份（TPM证书、PCR状态）
  
3. 运行时保护

   实时监测关键文件

### 代码结构
```
.
├── tpm-client
│   ├── aes.bin
│   ├── backup
│   ├── ca
│   ├── ca-test
│   ├── client_attestation.sh
│   ├── client.sh
│   ├── init_ak_ca.sh
│   ├── init_ek_ca.sh
│   ├── models
│   ├── privacy-ca
│   ├── sifive_client.sh
│   ├── test
│   ├── tpm2_debug.log
│   └── tpm-test
└── tpm-cloud
    ├── backup
    ├── ca
    ├── ca-test
    ├── cloud_attestation.sh
    ├── cloud.sh
    ├── decrypt_log.sh
    ├── ekcert.sh
    ├── extend_pcr10.sh
    ├── init_ak_ca.sh
    ├── init_ek_ca.sh
    ├── log
    ├── models
    ├── runtime_protect.sh
    ├── secure_audit.bin
    ├── secure_audit.log
    ├── test_performance.sh
    ├── tpm2_debug.log
    ├── tpm_runtime_protect.sh
    └── tpm-test
```
tpm-client目录中是客户端以及第三方CA相关代码

tpm-cloud目录中为云端相关代码

### 执行

##### 第三方CA初始化
执行tpm-cloud/init_ek_ca.sh和tpm-client/init_ak_ca.sh，初始化EK-CA和AK-CA。该脚本仅需执行一次。
##### 可信启动
在云端启动后，启动tpm-cloud/extend-pcr-10.sh，模拟启动度量。也可以编写成服务extend-pcr.service，在启动时自动度量。

由于实现所使用RISCV机器没有硬件可信根，故需要上述脚本模拟度量。若用户机器中含有硬件TPM芯片，无需执行该脚本。
##### 远程证明
在客户端和云端分别执行tpm-client/client.sh和tpm-cloud/cloud.sh，完成远程证明。
##### 运行时保护
在云端先启动runtime_protect.sh脚本，初始度量完成后，执行大模型相关应用。由于大模型参数文件较大，未上传至github，用户可自行从huggingface等网站获取模型。

### 其他
tpm-cloud与tpm-client之间的ssh通信请自行调整为对应ip地址或域名。若二者在同一PC中，可直接使用cp命令，并调整为对应路径即可。

其他详细描述可见毕设论文-基于硬件可信根的数据保护技术的设计与实现。

