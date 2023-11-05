#include "timer.h"

void setupOnePulse(void)
{

  TIM_TimeBaseInitTypeDef TIM_TimeBaseStructure;
  TIM_ICInitTypeDef       TIM_ICInitStructure;
  TIM_OCInitTypeDef       TIM_OCInitStructure;

  /* TIM Configuration */
  TIM_Config();

  
  /* Time base configuration */
  TIM_TimeBaseStructure.TIM_Period = 27;    // ARR
  TIM_TimeBaseStructure.TIM_Prescaler = 0;
  TIM_TimeBaseStructure.TIM_ClockDivision = 0;
  TIM_TimeBaseStructure.TIM_CounterMode = TIM_CounterMode_Up;

  TIM_TimeBaseInit(TIM4, &TIM_TimeBaseStructure);


  /* TIM4 PWM2 Mode configuration: Channel1 */
  TIM_OCInitStructure.TIM_OCMode = TIM_OCMode_PWM2;
  TIM_OCInitStructure.TIM_OutputState = TIM_OutputState_Enable;
  // 50 = 450ns between trigger and start of one pulse @240MHz
  // 40 = 370ns between trigger and start of one pulse @240MHz
  // 30 = 290ns between trigger and start of one pulse @240MHz
  // 20 = 210ns between trigger and start of one pulse @240MHz
  // so about 9ns per step
  TIM_OCInitStructure.TIM_Pulse = 18;        // CCR1
  TIM_OCInitStructure.TIM_OCPolarity = TIM_OCPolarity_High;

  TIM_OC1Init(TIM4, &TIM_OCInitStructure);

  /* TIM4 configuration in Input Capture Mode */

  TIM_ICStructInit(&TIM_ICInitStructure);

  TIM_ICInitStructure.TIM_Channel = TIM_Channel_2;
  TIM_ICInitStructure.TIM_ICPolarity = TIM_ICPolarity_Falling;
  TIM_ICInitStructure.TIM_ICSelection = TIM_ICSelection_DirectTI;
  TIM_ICInitStructure.TIM_ICPrescaler = TIM_ICPSC_DIV1;
  TIM_ICInitStructure.TIM_ICFilter = 0;

  TIM_ICInit(TIM4, &TIM_ICInitStructure);

  /* One Pulse Mode selection */
  TIM_SelectOnePulseMode(TIM4, TIM_OPMode_Single);

  /* Input Trigger selection */
  TIM_SelectInputTrigger(TIM4, TIM_TS_TI2FP2);

  /* Slave Mode selection: Trigger Mode */
  TIM_SelectSlaveMode(TIM4, TIM_SlaveMode_Trigger);

}

/**
  * @brief  Configure the TIM4 Pins.
  * @param  None
  * @retval None
  */
void TIM_Config(void)
{
  GPIO_InitTypeDef GPIO_InitStructure;

  /* TIM4 clock enable */
  RCC_APB1PeriphClockCmd(RCC_APB1Periph_TIM4, ENABLE);

  /* GPIOB clock enable */
  RCC_AHB1PeriphClockCmd(RCC_AHB1Periph_GPIOB, ENABLE);
  
  /* TIM4_CH1 pin (PB.06) configuration */
  GPIO_InitStructure.GPIO_Pin = GPIO_Pin_6;
  GPIO_InitStructure.GPIO_Mode = GPIO_Mode_AF;
  GPIO_InitStructure.GPIO_Speed = GPIO_Speed_100MHz;
  GPIO_InitStructure.GPIO_OType = GPIO_OType_PP;
  GPIO_InitStructure.GPIO_PuPd = GPIO_PuPd_NOPULL;
  GPIO_Init(GPIOB, &GPIO_InitStructure);

  /* TIM4_CH2 pin (PB.07) configuration */
  GPIO_InitStructure.GPIO_Pin = GPIO_Pin_7;
  GPIO_Init(GPIOB, &GPIO_InitStructure);

  /* Connect TIM pins to AF2 */
  GPIO_PinAFConfig(GPIOB, GPIO_PinSource6, GPIO_AF_TIM4);
  GPIO_PinAFConfig(GPIOB, GPIO_PinSource7, GPIO_AF_TIM4); 
    
}

