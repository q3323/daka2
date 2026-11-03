import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppIcon } from '../common/AppIcon';
import { IconPath } from '../common/IconPath';
import { AppColor, AppSize } from '../common/Theme';
import {
  AiChatMessage,
  AiChatResult,
  AiClient,
  AiPlanChange,
  AiPlanContext,
  AiPlanProposal
} from '../model/AiClient';
import { ApiClient, ApiResult } from '../model/ApiClient';
import { PlanItem } from '../model/DakaModel';

const DOMAIN: number = 0x0000;
const TAG: string = 'AIView';

class ApiMessageBody {
  message: string = '';
}

class AiPlanProposalEnvelope {
  proposal: AiPlanProposal = new AiPlanProposal();
}

class NormalizePlanResult {
  ok: boolean = false;
  message: string = '';
  proposal: AiPlanProposal = new AiPlanProposal();
}

@Component
export struct AIView {
  @Link baseUrl: string;
  @Link apiKey: string;
  @Link model: string;
  @Link plans: PlanItem[];
  @Prop authToken: string = '';
  @Prop initialMessages: AiChatMessage[] = [];
  onMessagesChanged: (messages: AiChatMessage[]) => void = () => {
  };
  onApplyPlanChanges: (changes: AiPlanChange[]) => void = () => {
  };

  @State messages: AiChatMessage[] = [];
  @State draft: string = '';
  @State sending: boolean = false;
  @State showSettings: boolean = true;
  @State planMode: boolean = false;
  @State pendingProposal: AiPlanProposal = new AiPlanProposal();

  aboutToAppear(): void {
    this.messages = this.initialMessages.slice();
    this.showSettings = this.baseUrl.length === 0
      || this.apiKey.length === 0
      || this.model.length === 0;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'toast failed: %{public}s', error.message);
    }
  }

  private saveSettings(): void {
    if (this.baseUrl.trim().length === 0
      || this.apiKey.trim().length === 0
      || this.model.trim().length === 0) {
      this.toast('请填写 Base URL、API Key 和模型名称');
      return;
    }
    this.showSettings = false;
    this.toast('接口配置已保存，仅当前 App 会话有效');
  }

  private appendAssistant(content: string): void {
    const next: AiChatMessage[] = this.messages.slice();
    next.push(new AiChatMessage('assistant', content));
    this.messages = next;
    this.onMessagesChanged(next);
  }

  private confirmClearMemory(): void {
    this.getUIContext().showAlertDialog({
      title: '清除 AI 对话记录？',
      message: '只会删除当前账号保存在本机的 AI 对话，不影响服务器数据和打卡计划。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清除',
        fontColor: AppColor.danger,
        action: () => {
          this.messages = [];
          this.pendingProposal = new AiPlanProposal();
          this.onMessagesChanged([]);
          this.toast('本地 AI 对话已清除');
        }
      }
    });
  }

  private planContexts(): AiPlanContext[] {
    const contexts: AiPlanContext[] = [];
    for (let i = 0; i < this.plans.length; i++) {
      const plan: PlanItem = this.plans[i];
      const context: AiPlanContext = new AiPlanContext();
      context.planId = plan.id;
      context.name = plan.name;
      context.timesPerDay = plan.timesPerDay;
      context.totalDays = plan.totalDays;
      context.remark = plan.remark;
      contexts.push(context);
    }
    return contexts;
  }

  private planIds(): string[] {
    const ids: string[] = [];
    for (let i = 0; i < this.plans.length; i++) {
      ids.push(this.plans[i].id);
    }
    return ids;
  }

  private apiMessage(result: ApiResult): string {
    if (result.body.length > 0) {
      try {
        const parsed: ApiMessageBody = JSON.parse(result.body) as ApiMessageBody;
        if (parsed.message !== undefined && parsed.message.length > 0) {
          return parsed.message;
        }
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'failed to parse plan API message');
      }
    }
    return result.message;
  }

  private async normalizeProposal(content: string): Promise<NormalizePlanResult> {
    const normalized: NormalizePlanResult = new NormalizePlanResult();
    const response: ApiResult = await ApiClient.normalizeAiPlanProposal(
      content,
      this.planIds(),
      this.authToken
    );
    if (!response.ok) {
      normalized.message = this.apiMessage(response);
      return normalized;
    }
    try {
      const parsed: AiPlanProposalEnvelope =
        JSON.parse(response.body) as AiPlanProposalEnvelope;
      if (parsed.proposal === undefined
        || parsed.proposal.plans === undefined
        || !Array.isArray(parsed.proposal.plans)
        || parsed.proposal.plans.length === 0) {
        normalized.message = '计划数据为空';
        return normalized;
      }
      normalized.ok = true;
      normalized.proposal = parsed.proposal;
      return normalized;
    } catch (err) {
      normalized.message = '无法读取计划数据';
      return normalized;
    }
  }

  private proposalText(proposal: AiPlanProposal): string {
    let text: string = proposal.summary;
    for (let i = 0; i < proposal.plans.length; i++) {
      const plan: AiPlanChange = proposal.plans[i];
      const action: string = plan.action === 'update' ? '修改' : '新增';
      text += `\n${action}：${plan.name} · 每天 ${plan.timesPerDay} 次 · ${plan.totalDays} 天`;
    }
    return text;
  }

  private async send(): Promise<void> {
    if (this.sending) {
      return;
    }
    const text: string = this.draft.trim();
    if (text.length === 0) {
      return;
    }
    if (this.baseUrl.trim().length === 0
      || this.apiKey.trim().length === 0
      || this.model.trim().length === 0) {
      this.showSettings = true;
      this.toast('请先配置 AI 接口');
      return;
    }
    if (this.planMode && this.authToken.length === 0) {
      this.toast('计划编辑需要先登录服务器账户');
      return;
    }

    const userMessage: AiChatMessage = new AiChatMessage('user', text);
    const withUser: AiChatMessage[] = this.messages.slice();
    withUser.push(userMessage);
    this.messages = withUser;
    this.onMessagesChanged(withUser);
    this.draft = '';
    this.sending = true;

    const history: AiChatMessage[] = withUser.slice();
    if (history.length > 24) {
      history.splice(0, history.length - 24);
    }
    if (this.planMode) {
      const contexts: AiPlanContext[] = this.planContexts();
      const result: AiChatResult = await AiClient.chatForPlan(
        this.baseUrl.trim(),
        this.apiKey.trim(),
        this.model.trim(),
        history,
        contexts
      );
      if (!result.ok) {
        this.appendAssistant(`计划生成失败：${result.message}`);
      } else {
        let normalized: NormalizePlanResult = await this.normalizeProposal(result.content);
        if (!normalized.ok) {
          const repaired: AiChatResult = await AiClient.repairPlan(
            this.baseUrl.trim(),
            this.apiKey.trim(),
            this.model.trim(),
            result.content,
            contexts
          );
          if (repaired.ok) {
            normalized = await this.normalizeProposal(repaired.content);
          }
        }
        if (normalized.ok) {
          this.pendingProposal = normalized.proposal;
          this.appendAssistant(this.proposalText(normalized.proposal));
        } else {
          this.appendAssistant(`计划格式校验失败：${normalized.message}`);
        }
      }
    } else {
      const result: AiChatResult = await AiClient.chat(
        this.baseUrl.trim(),
        this.apiKey.trim(),
        this.model.trim(),
        history
      );
      const reply: string = result.ok
        ? result.content
        : `请求失败：${result.message}`;
      this.appendAssistant(reply);
    }
    this.sending = false;
  }

  private applyPendingProposal(): void {
    if (this.pendingProposal.plans.length === 0) {
      return;
    }
    this.onApplyPlanChanges(this.pendingProposal.plans);
    this.pendingProposal = new AiPlanProposal();
    this.toast('计划已更新');
  }

  @Builder
  messageBubble(message: AiChatMessage) {
    Row() {
      if (message.role === 'user') {
        Blank()
      }
      Column() {
        Text(message.content)
          .fontSize(13)
          .fontColor(message.role === 'user' ? Color.White : AppColor.textMain)
          .lineHeight(20)
      }
      .padding(12)
      .backgroundColor(message.role === 'user' ? AppColor.primary : AppColor.card)
      .borderRadius(12)
      .constraintSize({ maxWidth: '84%' })
      if (message.role !== 'user') {
        Blank()
      }
    }
    .width('100%')
    .justifyContent(message.role === 'user' ? FlexAlign.End : FlexAlign.Start)
    .margin({ bottom: 10 })
  }

  @Builder
  settingsCard() {
    Column() {
      Row() {
        Column() {
          Text('AI 接口配置')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.textMain)
          Text('支持 OpenAI 兼容的 Chat Completions 接口')
            .fontSize(10)
            .fontColor(AppColor.textSub)
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('收起')
          .fontSize(11)
          .fontColor(AppColor.primary)
          .onClick(() => {
            this.showSettings = false;
          })
      }
      .width('100%')

      TextInput({ placeholder: 'Base URL，例如 https://api.example.com/v1', text: this.baseUrl })
        .height(40)
        .fontSize(12)
        .backgroundColor('#F5F7F9')
        .borderRadius(AppSize.radiusInner)
        .placeholderColor(AppColor.textWeak)
        .margin({ top: 12 })
        .onChange((value: string) => {
          this.baseUrl = value;
        })

      TextInput({ placeholder: 'API Key', text: this.apiKey })
        .type(InputType.Password)
        .height(40)
        .fontSize(12)
        .backgroundColor('#F5F7F9')
        .borderRadius(AppSize.radiusInner)
        .placeholderColor(AppColor.textWeak)
        .margin({ top: 8 })
        .onChange((value: string) => {
          this.apiKey = value;
        })

      TextInput({ placeholder: '模型名称', text: this.model })
        .height(40)
        .fontSize(12)
        .backgroundColor('#F5F7F9')
        .borderRadius(AppSize.radiusInner)
        .placeholderColor(AppColor.textWeak)
        .margin({ top: 8 })
        .onChange((value: string) => {
          this.model = value;
        })

      Row() {
        Text('API Key 只保存在当前 App 会话中')
          .fontSize(10)
          .fontColor(AppColor.textWeak)
          .layoutWeight(1)
        Button('保存配置')
          .fontSize(11)
          .fontColor(Color.White)
          .height(30)
          .padding({ left: 10, right: 10 })
          .backgroundColor(AppColor.primary)
          .onClick(() => {
            this.saveSettings();
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(AppColor.card)
    .borderRadius(AppSize.radiusCard)
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: AppSize.gap })
  }

  @Builder
  planProposalCard() {
    Column() {
      Row() {
        Column() {
          Text('待应用的计划')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.textMain)
          Text(this.pendingProposal.summary)
            .fontSize(11)
            .fontColor(AppColor.textSub)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(`${this.pendingProposal.plans.length} 项`)
          .fontSize(11)
          .fontColor(AppColor.primary)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(AppColor.primarySoft)
          .borderRadius(4)
      }
      .width('100%')

      Column() {
        ForEach(this.pendingProposal.plans, (plan: AiPlanChange) => {
          Row() {
            Text(plan.action === 'update' ? '修改' : '新增')
              .fontSize(10)
              .fontColor(plan.action === 'update' ? AppColor.info : AppColor.primary)
              .width(38)
            Text(plan.name)
              .fontSize(12)
              .fontColor(AppColor.textMain)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`每天 ${plan.timesPerDay} 次 · ${plan.totalDays} 天`)
              .fontSize(10)
              .fontColor(AppColor.textSub)
          }
          .width('100%')
          .padding({ top: 7, bottom: 7 })
        }, (plan: AiPlanChange, index: number) => `${index}_${plan.planId}_${plan.name}`)
      }
      .width('100%')
      .margin({ top: 6 })

      Button('应用这些计划')
        .fontSize(12)
        .fontColor(Color.White)
        .height(38)
        .width('100%')
        .backgroundColor(AppColor.primary)
        .margin({ top: 10 })
        .onClick(() => {
          this.applyPendingProposal();
        })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(AppColor.card)
    .borderRadius(AppSize.radiusCard)
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 4, bottom: AppSize.gap })
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text('AI 助手')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.textMain)
          Text('生成学习建议，确认后可直接更新计划')
            .fontSize(11)
            .fontColor(AppColor.textSub)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.messages.length > 0) {
          Button({ type: ButtonType.Circle }) {
            AppIcon({ commands: IconPath.trash, iconSize: 14, color: AppColor.danger, strokeW: 1.8 })
          }
          .width(34)
          .height(34)
          .backgroundColor(AppColor.dangerSoft)
          .margin({ right: 8 })
          .onClick(() => {
            this.confirmClearMemory();
          })
        }

        Button({ type: ButtonType.Capsule }) {
          Row() {
            AppIcon({ commands: IconPath.ai, iconSize: 14, color: AppColor.primary, strokeW: 1.8 })
            Text('接口设置')
              .fontSize(11)
              .fontColor(AppColor.primary)
              .margin({ left: 4 })
          }
        }
        .height(34)
        .padding({ left: 10, right: 10 })
        .backgroundColor(AppColor.primarySoft)
        .onClick(() => {
          this.showSettings = true;
        })
      }
      .width('100%')

      if (this.showSettings) {
        this.settingsCard()
      }

      Row() {
        Column() {
          Text('计划编辑模式')
            .fontSize(12)
            .fontColor(AppColor.textMain)
          Text(this.planMode ? 'AI 将生成可应用的计划 JSON' : '普通对话模式')
            .fontSize(10)
            .fontColor(AppColor.textSub)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.planMode })
          .selectedColor(AppColor.primary)
          .onChange((isOn: boolean) => {
            this.planMode = isOn;
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(AppColor.card)
      .borderRadius(AppSize.radiusInner)
      .margin({ bottom: AppSize.gap })

      Scroll() {
        Column() {
          if (this.messages.length === 0) {
            Column() {
              Column() {
                AppIcon({ commands: IconPath.ai, iconSize: 30, color: AppColor.primary, strokeW: 1.6 })
              }
              .width(58)
              .height(58)
              .borderRadius(29)
              .backgroundColor(AppColor.primarySoft)
              .justifyContent(FlexAlign.Center)

              Text('有什么可以帮你？')
                .fontSize(14)
                .fontColor(AppColor.textMain)
                .margin({ top: 12 })
              Text(this.planMode ? '描述你想制定或调整的打卡计划' : '可以问学习规划、数据分析或项目复盘建议')
                .fontSize(11)
                .fontColor(AppColor.textSub)
                .margin({ top: 5 })
            }
            .width('100%')
            .padding({ top: 44, bottom: 44 })
            .justifyContent(FlexAlign.Center)
          } else {
            ForEach(this.messages, (message: AiChatMessage) => {
              this.messageBubble(message)
            }, (message: AiChatMessage, index: number) => `${index}_${message.role}`)

            if (this.sending) {
              Row() {
                Text('AI 正在思考...')
                  .fontSize(11)
                  .fontColor(AppColor.textSub)
              }
              .width('100%')
              .padding({ top: 6, bottom: 10 })
            }
          }

          if (this.pendingProposal.plans.length > 0) {
            this.planProposalCard()
          }
        }
        .width('100%')
        .padding({ top: 14, bottom: 10 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      Column() {
        Row() {
          TextArea({ placeholder: '输入你的问题...', text: this.draft })
            .height(64)
            .fontSize(13)
            .layoutWeight(1)
            .backgroundColor('#F5F7F9')
            .borderRadius(AppSize.radiusInner)
            .placeholderColor(AppColor.textWeak)
            .maxLength(1000)
            .onChange((value: string) => {
              this.draft = value;
            })
          Button(this.sending ? '发送中' : '发送')
            .fontSize(12)
            .fontColor(Color.White)
            .height(40)
            .width(64)
            .backgroundColor(AppColor.primary)
            .margin({ left: 8 })
            .enabled(!this.sending)
            .onClick(() => {
              this.send();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)

        Text(this.planMode
          ? '计划只会显示为提案，点击“应用这些计划”后才会写入'
          : '对话记录仅保存在本机的当前账号')
          .fontSize(9)
          .fontColor(AppColor.textWeak)
          .width('100%')
          .margin({ top: 5 })
      }
      .width('100%')
      .padding({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .padding(AppSize.pagePadding)
    .backgroundColor(AppColor.pageBg)
    .alignItems(HorizontalAlign.Start)
  }
}
