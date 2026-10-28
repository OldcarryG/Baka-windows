using System.Windows;
using System.Windows.Markup;
using System.Windows.Media;

namespace Baka.Desktop
{
    // Implicit dark styles for the stock WPF controls BAKA uses (text boxes, scroll bars, sliders, tool tips,
    // context menus, list items), bound to theme brushes that are swapped when the theme changes.
    static class Styles
    {
        const string Xaml = @"
<ResourceDictionary xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>
  <Style TargetType='TextBox'>
    <Setter Property='Foreground' Value='{DynamicResource Baka.Text}'/>
    <Setter Property='CaretBrush' Value='{DynamicResource Baka.Accent}'/>
    <Setter Property='SelectionBrush' Value='{DynamicResource Baka.Accent}'/>
    <Setter Property='FontFamily' Value='Segoe UI Variable Text, Segoe UI'/>
    <Setter Property='FontSize' Value='13'/>
    <Setter Property='Padding' Value='10,6'/>
    <Setter Property='Template'>
      <Setter.Value>
        <ControlTemplate TargetType='TextBox'>
          <Border x:Name='b' CornerRadius='9' Background='{DynamicResource Baka.Field}' BorderBrush='{DynamicResource Baka.Border}' BorderThickness='1'>
            <ScrollViewer x:Name='PART_ContentHost' Margin='{TemplateBinding Padding}' VerticalAlignment='Center'/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property='IsKeyboardFocused' Value='True'><Setter TargetName='b' Property='BorderBrush' Value='{DynamicResource Baka.Accent}'/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType='ScrollBar'>
    <Setter Property='Width' Value='8'/>
    <Setter Property='MinWidth' Value='8'/>
    <Setter Property='Template'>
      <Setter.Value>
        <ControlTemplate TargetType='ScrollBar'>
          <Track x:Name='PART_Track' IsDirectionReversed='True'>
            <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType='Thumb'><Border CornerRadius='4' Margin='1' Background='{DynamicResource Baka.Thumb}'/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
          </Track>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
    <Style.Triggers>
      <Trigger Property='Orientation' Value='Horizontal'>
        <Setter Property='Height' Value='8'/><Setter Property='MinHeight' Value='8'/><Setter Property='Width' Value='Auto'/>
        <Setter Property='Template'>
          <Setter.Value>
            <ControlTemplate TargetType='ScrollBar'>
              <Track x:Name='PART_Track' IsDirectionReversed='False'>
                <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType='Thumb'><Border CornerRadius='4' Margin='1' Background='{DynamicResource Baka.Thumb}'/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
              </Track>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Trigger>
    </Style.Triggers>
  </Style>
  <Style TargetType='Slider'>
    <Setter Property='Template'>
      <Setter.Value>
        <ControlTemplate TargetType='Slider'>
          <Grid Height='22'>
            <Border Height='4' CornerRadius='2' Background='{DynamicResource Baka.Field}' VerticalAlignment='Center'/>
            <Track x:Name='PART_Track'>
              <Track.DecreaseRepeatButton><RepeatButton Command='Slider.DecreaseLarge'><RepeatButton.Template><ControlTemplate><Border Height='4' CornerRadius='2' Background='{DynamicResource Baka.Accent}'/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.DecreaseRepeatButton>
              <Track.IncreaseRepeatButton><RepeatButton Command='Slider.IncreaseLarge'><RepeatButton.Template><ControlTemplate><Border Background='Transparent'/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.IncreaseRepeatButton>
              <Track.Thumb><Thumb><Thumb.Template><ControlTemplate><Ellipse Width='16' Height='16' Fill='{DynamicResource Baka.Text}' Stroke='{DynamicResource Baka.Accent}' StrokeThickness='2'/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
            </Track>
          </Grid>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType='ToolTip'>
    <Setter Property='Foreground' Value='{DynamicResource Baka.Text}'/>
    <Setter Property='FontFamily' Value='Segoe UI Variable Text, Segoe UI'/>
    <Setter Property='Template'>
      <Setter.Value>
        <ControlTemplate TargetType='ToolTip'>
          <Border CornerRadius='8' Background='{DynamicResource Baka.Menu}' BorderBrush='{DynamicResource Baka.Border}' BorderThickness='1' Padding='9,5'>
            <ContentPresenter TextElement.Foreground='{DynamicResource Baka.Text}'/>
          </Border>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType='ContextMenu'>
    <Setter Property='Template'>
      <Setter.Value>
        <ControlTemplate TargetType='ContextMenu'>
          <Border CornerRadius='10' Background='{DynamicResource Baka.Menu}' BorderBrush='{DynamicResource Baka.Border}' BorderThickness='1' Padding='4'>
            <StackPanel IsItemsHost='True'/>
          </Border>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType='Separator'>
    <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='Separator'><Border Height='1' Margin='8,4' Background='{DynamicResource Baka.Border}'/></ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType='MenuItem'>
    <Setter Property='Foreground' Value='{DynamicResource Baka.Text}'/>
    <Setter Property='FontFamily' Value='Segoe UI Variable Text, Segoe UI'/>
    <Setter Property='FontSize' Value='12.5'/>
    <Setter Property='Template'>
      <Setter.Value>
        <ControlTemplate TargetType='MenuItem'>
          <Border x:Name='b' CornerRadius='7' Padding='10,6' Background='Transparent' MinWidth='190'>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width='24'/><ColumnDefinition/><ColumnDefinition Width='Auto'/></Grid.ColumnDefinitions>
              <ContentPresenter ContentSource='Icon' VerticalAlignment='Center'/>
              <ContentPresenter Grid.Column='1' ContentSource='Header' VerticalAlignment='Center'/>
              <TextBlock Grid.Column='2' Text='{TemplateBinding InputGestureText}' Margin='16,0,0,0' Foreground='{DynamicResource Baka.Muted}' VerticalAlignment='Center'/>
            </Grid>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property='IsHighlighted' Value='True'><Setter TargetName='b' Property='Background' Value='{DynamicResource Baka.Hover}'/></Trigger>
            <Trigger Property='IsEnabled' Value='False'><Setter Property='Opacity' Value='0.45'/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType='ListBoxItem'>
    <Setter Property='Template'>
      <Setter.Value>
        <ControlTemplate TargetType='ListBoxItem'>
          <Border x:Name='b' CornerRadius='7' Padding='{TemplateBinding Padding}' Background='Transparent'><ContentPresenter/></Border>
          <ControlTemplate.Triggers>
            <Trigger Property='IsMouseOver' Value='True'><Setter TargetName='b' Property='Background' Value='{DynamicResource Baka.Hover}'/></Trigger>
            <Trigger Property='IsSelected' Value='True'><Setter TargetName='b' Property='Background' Value='{DynamicResource Baka.Selected}'/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType='ListBox'>
    <Setter Property='Background' Value='Transparent'/>
    <Setter Property='BorderThickness' Value='0'/>
    <Setter Property='Foreground' Value='{DynamicResource Baka.Text}'/>
  </Style>
</ResourceDictionary>";

        static ResourceDictionary dictionary;
        public static void Install(Application app)
        {
            dictionary = (ResourceDictionary)XamlReader.Parse(Xaml);
            app.Resources.MergedDictionaries.Add(dictionary);
            Update();
            Theme.Changed += Update;
        }
        static void Update()
        {
            var r = Application.Current.Resources;
            r["Baka.Text"] = Theme.Text; r["Baka.Muted"] = Theme.Muted; r["Baka.Accent"] = Theme.Accent; r["Baka.Border"] = Theme.Border; r["Baka.Hover"] = Theme.Hover;
            r["Baka.Field"] = Theme.B(Theme.Current.SurfaceAlt, 200); r["Baka.Thumb"] = Theme.B(Theme.Current.Text, 70);
            r["Baka.Menu"] = Theme.B(Theme.Current.Surface, 250); r["Baka.Selected"] = new SolidColorBrush(Theme.C(Theme.AccentHex, 60));
        }
    }
}
