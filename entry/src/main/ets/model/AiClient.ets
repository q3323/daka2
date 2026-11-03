import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'AiClient';

export class AiChatMessage {
  role: string = '';
  content: string = '';

  constructor(role: string, content: string) {
    this.role = role;
    this.content = content;
  }
}

export class AiChatResult {
  ok: boolean = false;
  message: string = '';
  content: string = '';
}

export class AiPlanContext {
  planId: string = '';
  name: string = '';
  timesPerDay: number = 1;
  totalDays: number = 7;
  remark: string = '';
}

export class AiPlanChange {
  action: string = 'add';
  planId: string = '';
  name: string = '';
  timesPerDay: number = 1;
  totalDays: number = 7;
  remark: string = '';
}

export class AiPlanProposal {
  summary: string = '';
  plans: AiPlanChange[] = [];
}

class AiResponseMessage {
  content: string = '';
}

class AiResponseChoice {
  message: AiResponseMessage = new AiResponseMessage();
}

class AiErrorBody {
  message: string = '';
}

class AiResponseBody {
  choices: AiResponseChoice[] = [];
  error: AiErrorBody = new AiErrorBody();
}

export class AiClient {
  static async chat(baseUrl: string, apiKey: string, model: string,
    history: AiChatMessage[]): Promise<AiChatResult> {
    const messages: AiChatMessage[] = [];
    messages.push(new AiChatMessage(
      'system',
      '你是学习计划和数据分析学习助手。你只能提供建议、解释和示例，' +
      '不能声称已经修改用户的计划，也不能直接写入或删除用户数据。' +
      '如果用户要求修改计划，请提示用户在计划页面手动操作。请使用中文回答。'
    ));
    for (let i = 0; i < history.length; i++) {
      messages.push(history[i]);
    }
    return AiClient.request(baseUrl, apiKey, model, messages, 0.7);
  }

  static async chatForPlan(baseUrl: string, apiKey: string, model: string,
    history: AiChatMessage[], plans: AiPlanContext[]): Promise<AiChatResult> {
    const messages: AiChatMessage[] = [];
    messages.push(new AiChatMessage('system', AiClient.planSystemPrompt(plans)));
    for (let i = 0; i < history.length; i++) {
      messages.push(history[i]);
    }
    return AiClient.request(baseUrl, apiKey, model, messages, 0.2);
  }

  static async repairPlan(baseUrl: string, apiKey: string, model: string,
    rawOutput: string, plans: AiPlanContext[]): Promise<AiChatResult> {
    const messages: AiChatMessage[] = [];
    messages.push(new AiChatMessage('system', AiClient.planSystemPrompt(plans)));
    messages.push(new AiChatMessage(
      'user',
      '请把下面的内容转换成指定 JSON。不要解释，不要使用 Markdown：\n' +
      rawOutput.substring(0, 12000)
    ));
    return AiClient.request(baseUrl, apiKey, model, messages, 0.1);
  }

  private static async request(baseUrl: string, apiKey: string, model: string,
    messages: AiChatMessage[], temperature: number): Promise<AiChatResult> {
    const result: AiChatResult = new AiChatResult();
    const url: string = AiClient.chatEndpoint(baseUrl);
    if (url.length === 0) {
      result.message = '请填写 API 基础地址';
      return result;
    }
    if (apiKey.length === 0) {
      result.message = '请填写 API Key';
      return result;
    }
    if (model.length === 0) {
      result.message = '请填写模型名称';
      return result;
    }

    const body: string = JSON.stringify({
      model: model,
      messages: messages,
      temperature: temperature,
      stream: false
    });

    const request: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`
        },
        extraData: body,
        connectTimeout: 15000,
        readTimeout: 60000,
        usingCache: false
      };
      const response: http.HttpResponse = await request.request(url, options);
      const raw: string = typeof response.result === 'string'
        ? response.result
        : JSON.stringify(response.result);
      result.ok = response.responseCode >= 200 && response.responseCode < 300;
      if (!result.ok) {
        result.message = AiClient.errorMessage(raw, response.responseCode);
        return result;
      }

      const parsed: AiResponseBody = JSON.parse(raw) as AiResponseBody;
      if (parsed.choices === undefined || parsed.choices.length === 0
        || parsed.choices[0].message === undefined
        || parsed.choices[0].message.content.length === 0) {
        result.message = 'AI 没有返回有效内容';
        return result;
      }
      result.content = parsed.choices[0].message.content;
      return result;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      result.message = error.message.length > 0 ? error.message : 'AI 请求失败';
      hilog.error(DOMAIN, TAG, 'chat failed: %{public}s', result.message);
      return result;
    } finally {
      request.destroy();
    }
  }

  private static planSystemPrompt(plans: AiPlanContext[]): string {
    return '你是打卡计划编辑助手。根据用户需求制定或修改计划。' +
      '当前用户已有的计划如下，必须严格使用其中的 planId 修改已有计划：\n' +
      `${JSON.stringify(plans)}\n` +
      '只允许两种 action：add 新建计划，update 修改已有计划；禁止删除计划。' +
      '每次最多返回 10 项，timesPerDay 必须是 1 到 20 的整数，' +
      'totalDays 必须是 1 到 365 的整数。' +
      '只返回一个 JSON 对象，不要使用 Markdown，不要添加 JSON 之外的解释。' +
      'JSON 必须严格符合：' +
      '{"summary":"简短说明","plans":[{"action":"add","planId":"",' +
      '"name":"计划名","timesPerDay":1,"totalDays":7,"remark":"备注"}]}。' +
      'update 时 planId 必须填写当前计划中真实存在的编号；add 时 planId 为空。';
  }

  private static chatEndpoint(baseUrl: string): string {
    let value: string = baseUrl.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.length === 0) {
      return '';
    }
    if (value.endsWith('/chat/completions')) {
      return value;
    }
    return `${value}/chat/completions`;
  }

  private static errorMessage(raw: string, statusCode: number): string {
    try {
      const parsed: AiResponseBody = JSON.parse(raw) as AiResponseBody;
      if (parsed.error !== undefined && parsed.error.message.length > 0) {
        return parsed.error.message;
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'failed to parse AI error body');
    }
    return `AI 请求失败，HTTP ${statusCode}`;
  }
}
