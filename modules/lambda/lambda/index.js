const { SESClient, SendRawEmailCommand } = require("@aws-sdk/client-ses");
const ses = new SESClient({ region: process.env.AWS_REGION || "us-east-1" });

const getHeader = (title, color) => `
  <div style="background-color: ${color}; padding: 25px; text-align: center; color: white; border-top-left-radius: 8px; border-top-right-radius: 8px;">
    <h2 style="margin: 0; font-size: 22px; font-weight: bold; letter-spacing: 0.5px; font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;">${title}</h2>
  </div>
`;

const getFooter = (env) => `
  <div style="background-color: #f8f9fa; padding: 15px 30px; text-align: center; font-size: 12px; color: #888; border-bottom-left-radius: 8px; border-bottom-right-radius: 8px; border-top: 1px solid #eee; font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;">
    <p style="margin: 0; font-weight: bold; color: #555;">Procurement Platform Monitor [Environment: ${env.toUpperCase()}]</p>
    <p style="margin: 4px 0 0 0; font-size: 11px; color: #aaa;">This is an automated notification from AWS CloudWatch/EventBridge. Please do not reply.</p>
  </div>
`;

const getTable = (rows) => `
  <table style="width: 100%; border-collapse: collapse; margin: 20px 0; font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;">
    <tbody>
      ${rows.map(row => `
        <tr>
          <td style="padding: 12px 15px; border-bottom: 1px solid #f0f0f0; font-weight: bold; width: 35%; color: #666; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">${row.label}</td>
          <td style="padding: 12px 15px; border-bottom: 1px solid #f0f0f0; color: #333; font-size: 14px; word-break: break-all; font-family: Consolas, Monaco, monospace;">${row.value}</td>
        </tr>
      `).join('')}
    </tbody>
  </table>
`;

const getTemplateWrapper = (headerTitle, headerColor, introText, rows, env) => `
  <!DOCTYPE html>
  <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
    </head>
    <body style="font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; background-color: #f4f5f7; margin: 0; padding: 30px 15px;">
      <div style="background-color: #ffffff; border-radius: 8px; max-width: 600px; margin: 0 auto; box-shadow: 0 4px 12px rgba(0,0,0,0.05); overflow: hidden; border: 1px solid #e1e4e8;">
        ${getHeader(headerTitle, headerColor)}
        <div style="padding: 30px;">
          <p style="font-size: 16px; line-height: 1.6; color: #444; margin: 0 0 20px 0;">${introText}</p>
          ${getTable(rows)}
        </div>
        ${getFooter(env)}
      </div>
    </body>
  </html>
`;

const send_email = async (subject, html_body) => {
  const sender = process.env.SENDER_EMAIL;
  const recipient = process.env.RECIPIENT_EMAIL;

  if (!sender || !recipient) {
    throw new Error("SENDER_EMAIL or RECIPIENT_EMAIL environment variables are not set");
  }

  const boundary = `----=_Part_${Math.random().toString(36).substring(2)}`;
  
  const rawMessage = [
    `From: ${sender}`,
    `To: ${recipient}`,
    `Subject: ${subject}`,
    `MIME-Version: 1.0`,
    `Content-Type: multipart/alternative; boundary="${boundary}"`,
    ``,
    `--${boundary}`,
    `Content-Type: text/html; charset=UTF-8`,
    `Content-Transfer-Encoding: 7bit`,
    ``,
    html_body,
    ``,
    `--${boundary}--`
  ].join("\r\n");

  const rawBytes = Buffer.from(rawMessage, "utf-8");

  const command = new SendRawEmailCommand({
    RawMessage: {
      Data: rawBytes
    }
  });

  return await ses.send(command);
};

exports.handler = async (event) => {
  console.log("Received Event:", JSON.stringify(event, null, 2));

  for (const record of event.Records) {
    const sns = record.Sns;
    const subject = sns.Subject || "Procurement Platform Notification";
    const messageStr = sns.Message;
    
    let message;
    try {
      message = JSON.parse(messageStr);
    } catch (e) {
      message = messageStr;
    }

    let emailSubject = subject;
    let emailHtml = "";
    const env = process.env.ENVIRONMENT || "dev";

    if (typeof message === "object" && message.AlarmName) {
      // CloudWatch Alarm Event
      const alarmName = message.AlarmName;
      const newState = message.NewStateValue;
      const reason = message.NewStateReason;
      const time = message.StateChangeTime || new Date().toISOString();
      const metric = message.Trigger?.MetricName || "Metric";
      const threshold = message.Trigger?.Threshold || "N/A";
      
      const isScaleOut = alarmName.toLowerCase().includes("high");

      if (isScaleOut) {
        emailSubject = `🚀 Scale Out Alert | ${alarmName}`;
        emailHtml = getTemplateWrapper(
          "🚀 SCALE OUT ALERT",
          "#d9534f",
          "An auto-scaling high resource usage alarm was triggered. The environment is scaling out to meet demand.",
          [
            { label: "Alarm Name", value: alarmName },
            { label: "State", value: `<span style="background-color: #d9534f; color: white; padding: 4px 8px; border-radius: 4px; font-weight: bold; font-size: 11px;">${newState}</span>` },
            { label: "Metric", value: metric },
            { label: "Threshold", value: `${threshold}%` },
            { label: "Time", value: time },
            { label: "Environment", value: env.toUpperCase() },
            { label: "Recommended Action", value: "Monitor ASG activity and target group health to verify successful instance provision." }
          ],
          env
        );
      } else {
        emailSubject = `⚠ Scale In Alert | ${alarmName}`;
        emailHtml = getTemplateWrapper(
          "⚠ SCALE IN ALERT",
          "#f0ad4e",
          "An auto-scaling low resource usage alarm was triggered. The environment is scaling in to conserve resources.",
          [
            { label: "Alarm Name", value: alarmName },
            { label: "State", value: `<span style="background-color: #f0ad4e; color: white; padding: 4px 8px; border-radius: 4px; font-weight: bold; font-size: 11px;">${newState}</span>` },
            { label: "Metric", value: metric },
            { label: "Threshold", value: `${threshold}%` },
            { label: "Time", value: time },
            { label: "Environment", value: env.toUpperCase() }
          ],
          env
        );
      }
    } else if (typeof message === "object" && message.source === "aws.autoscaling") {
      // EventBridge ASG Lifecycle Event
      const detailType = message["detail-type"];
      const asgName = message.detail.AutoScalingGroupName;
      const instanceId = message.detail.EC2InstanceId;
      const time = message.time || new Date().toISOString();

      if (detailType === "EC2 Instance Launch Successful") {
        emailSubject = `🖥 EC2 Instance Launched`;
        emailHtml = getTemplateWrapper(
          "🖥 INSTANCE LAUNCH SUCCESSFUL",
          "#0275d8",
          "A new EC2 instance has been successfully launched by Auto Scaling in response to scaling policy demands.",
          [
            { label: "Instance ID", value: instanceId },
            { label: "ASG Name", value: asgName },
            { label: "Launch Time", value: time },
            { label: "Environment", value: env.toUpperCase() }
          ],
          env
        );
      } else if (detailType === "EC2 Instance Terminate Successful") {
        emailSubject = `🗑 EC2 Instance Terminated`;
        emailHtml = getTemplateWrapper(
          "🗑 INSTANCE TERMINATION SUCCESSFUL",
          "#373a3c",
          "An existing EC2 instance has been successfully terminated by Auto Scaling as part of scaling-in operations.",
          [
            { label: "Instance ID", value: instanceId },
            { label: "ASG Name", value: asgName },
            { label: "Termination Time", value: time },
            { label: "Environment", value: env.toUpperCase() }
          ],
          env
        );
      } else {
        emailSubject = `ASG Event: ${detailType}`;
        emailHtml = getTemplateWrapper(
          "ASG EVENT NOTIFICATION",
          "#0275d8",
          "An Auto Scaling Group activity has occurred.",
          [
            { label: "Event Type", value: detailType },
            { label: "ASG Name", value: asgName },
            { label: "Time", value: time },
            { label: "Environment", value: env.toUpperCase() }
          ],
          env
        );
      }
    } else {
      // Fallback
      emailSubject = `Notification: ${subject}`;
      emailHtml = getTemplateWrapper(
        "🔔 SYSTEM NOTIFICATION",
        "#0275d8",
        "A notification was dispatched to the monitoring service.",
        [
          { label: "Subject", value: subject },
          { label: "Details", value: typeof message === 'object' ? JSON.stringify(message) : message }
        ],
        env
      );
    }

    try {
      const res = await send_email(emailSubject, emailHtml);
      console.log(`SES raw HTML email alert sent: ${res.MessageId}`);
    } catch (err) {
      console.error("Error sending SES raw email:", err);
    }
  }
};
