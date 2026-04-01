using System.Windows;

namespace ScreenshotTool;

public partial class OnboardingWindow : Window
{
    public OnboardingWindow()
    {
        InitializeComponent();
    }

    private void Next1_Click(object sender, RoutedEventArgs e)
    {
        Page1.Visibility = Visibility.Collapsed;
        Page2.Visibility = Visibility.Visible;
    }

    private void Next2_Click(object sender, RoutedEventArgs e)
    {
        Page2.Visibility = Visibility.Collapsed;
        Page3.Visibility = Visibility.Visible;
    }

    private void Finish_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = true;
        Close();
    }
}
