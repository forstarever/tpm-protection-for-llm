#!/bin/bash
set -e  # 任何命令失败则终止脚本

# 配置路径
CLOUD_DIR="/home/star/tpm/tpm-test"
CLIENT_DIR="/home/star/tpm/tpm-test"  # 用户端目录
CLIENT_IP="vmware-ubuntu"        # 用户端IP或域名

# 创建清理函数
cleanup() {
    echo "[清理] 正在清除临时文件..."
    shred -u "$CLOUD_DIR"/* 2>/dev/null || true
    echo "[清理] 完成"
}

# 设置trap捕获EXIT信号
trap cleanup EXIT

mkdir -p $CLOUD_DIR
cd $CLOUD_DIR

# 定义EK的持久化句柄
EK_HANDLE=0x81010001

# 步骤1: 检查EK是否已持久化
if tpm2_getcap handles-persistent | grep -q $EK_HANDLE; then
  tpm2_readpublic -Q -c $EK_HANDLE  -o ek.pub
  echo "EK (句柄 $EK_HANDLE) 已存在，跳过创建。"
else
  echo "EK (句柄 $EK_HANDLE) 未找到，开始创建并持久化..."
  # 生成EK并保存到临时上下文文件
  tpm2_createek -Q -c ek_temp.ctx -G rsa -u ek.pub
  # 持久化EK到指定句柄（需要所有者权限）
  tpm2_evictcontrol -C o -c ek_temp.ctx $EK_HANDLE
  # 清理临时文件
  rm ek_temp.ctx
  echo "EK已持久化到句柄 $EK_HANDLE。"
fi

# 步骤2: 创建AIK（绑定到持久化的EK）
echo "创建AIK..."
tpm2_createak -C $EK_HANDLE -c ak.ctx -G rsa -g sha256 -s rsassa -u ak.pub \
  -n ak.name -p akpass
echo "AIK创建完成。"

# 将公钥传输到用户端（需提前配置SSH免密登录）
echo "[Cloud] 传输EK/AIK公钥到用户端..."
scp ek.pub ak.pub ak.name $CLIENT_IP:$CLIENT_DIR/

# 步骤2: 等待用户发送Nonce，接收后生成Quote
echo "[Cloud] 等待用户发送Nonce..."
until [ -f $CLOUD_DIR/nonce.bin ]; do sleep 2; done

echo "[Cloud] 生成Quote..."
tpm2_quote -Q -c ak.ctx -p akpass -l sha1:10 -q $(cat nonce.bin) -m quote.msg -s quote.sig -o quote.pcrs -g sha256

# 传输Quote到用户端
scp quote.msg quote.sig quote.pcrs $CLIENT_IP:$CLIENT_DIR/

# 步骤3: 接收用户凭证并激活密钥
echo "[Cloud] 等待用户发送凭证..."
while true; do
    if [ -f $CLOUD_DIR/aescred.out ]; then
        echo "[Cloud] 接收到凭证，准备激活..."
        break
    fi
    if [ -f $CLOUD_DIR/auth_failed.log ]; then
        echo "[Cloud] 警告：用户端验证失败，远程证明终止！"
        exit 1
    fi
    sleep 2
done

echo "[Cloud] 激活凭证..."
tpm2_startauthsession --policy-session -S session.ctx
tpm2_policysecret -S session.ctx -c e
if tpm2_activatecredential -Q -c ak.ctx -C 0x81010001 -i aescred.out -o aes.bin -p akpass -P"session:session.ctx"; then
    echo "[SUCCESS] 解封成功，平台可信，准备解密模型..."
else
    echo "[ERROR] 密钥解封失败，平台不可信，终止操作。"
    tpm2_flushcontext session.ctx
    exit 1
fi

# 步骤4: 解密模型文件
echo "[Cloud] 解密模型"
START_DECRYPT=$(date +%s%3N)
openssl enc -d -aes-256-cbc -salt -pbkdf2 -in $CLOUD_DIR/../backup/model.enc -out $CLOUD_DIR/../models/model.guff -pass file:aes.bin
END_DECRYPT=$(date +%s%3N)
ELAPSED=$((END_DECRYPT - START_DECRYPT))
echo "[RESULT] 模型解密耗时：$ELAPSED ms"
echo "[Cloud] 远程认证与解密完成！解密模型：model.guff"
